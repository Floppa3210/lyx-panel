--[[
    LyxPanel - Report System (Hardened)

    Goals:
    - Player reports (/report) persisted in DB (managed by migrations.lua)
    - Admin notifications + optional Discord webhook
    - Strict validation + rate-limit + permissions for admin-side actions

    NOTE:
    - This module does NOT create tables at runtime. Use versioned migrations.
    - DB schema: lyxpanel_reports, lyxpanel_report_messages
]]

local ReportSystem = {}

-- Configuration (keep minimal here; advanced values live in config.lua)
local Settings = {
    enabled = true,
    cooldownSeconds = 60, -- per reporter
    maxActiveReports = 50, -- global open/in_progress limit (DB-backed)
    reportCommand = 'report',
    callAdminCommand = 'calladmin',
    screenshotOnReport = false
}

-- Cooldowns per player (memory only; resets on restart)
local ReportCooldowns = {}

local _ActionCooldowns = {}

local function _IsRateLimited(src, key, cooldownMs)
    if not src or src <= 0 then return true end
    cooldownMs = tonumber(cooldownMs) or 0

    local now = GetGameTimer()
    _ActionCooldowns[src] = _ActionCooldowns[src] or {}
    local last = _ActionCooldowns[src][key] or 0
    if (now - last) < cooldownMs then
        return true
    end
    _ActionCooldowns[src][key] = now
    return false
end

local function _GetLimitNumber(name, fallback)
    local limits = Config and Config.ActionLimits or nil
    local v = limits and limits[name]
    if type(v) == 'number' then
        return v
    end
    return fallback
end

local function _GetCooldownMs(key, fallback)
    local limits = Config and Config.ActionLimits or nil
    local v = limits and limits.cooldownMs and limits.cooldownMs[key]
    if type(v) == 'number' then
        return v
    end
    return fallback
end

local function _SanitizeText(s, maxLen)
    if LyxPanelLib and LyxPanelLib.Sanitize then
        return LyxPanelLib.Sanitize(s, maxLen)
    end
    s = tostring(s or ''):gsub('[%c]', ''):gsub('[\r\n\t]', ' ')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function GetId(source, idType)
    idType = idType or 'license'
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, idType .. ':') then
            return id
        end
    end
    return nil
end

local function _IsAdminForReports(source)
    if type(HasPermission) == 'function' then
        return HasPermission(source, 'canManageReports') == true
    end
    return IsPlayerAceAllowed(source, 'lyxpanel.admin') or IsPlayerAceAllowed(source, 'lyxpanel.access')
end

local function _FindOnlineByLicense(license)
    if type(license) ~= 'string' or license == '' then return nil end
    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        if pid and GetPlayerName(pid) then
            local lid = GetId(pid, 'license')
            if lid == license then
                return pid
            end
        end
    end
    return nil
end

local _PriorityRank = {
    low = 1,
    medium = 2,
    high = 3,
    critical = 4
}

local _DefaultRunbooks = {
    low = {
        { id = 'ack', title = 'Acusar recibo', description = 'Confirmar recepcion al jugador reportante.' },
        { id = 'review_context', title = 'Revisar contexto', description = 'Leer razon completa y validar datos basicos.' },
        { id = 'close_note', title = 'Cerrar con nota', description = 'Documentar cierre en reporte y log.' }
    },
    medium = {
        { id = 'ack', title = 'Acusar recibo', description = 'Confirmar recepcion al jugador reportante.' },
        { id = 'contact_players', title = 'Contactar involucrados', description = 'Pedir version breve a reportante y reportado.' },
        { id = 'collect_evidence', title = 'Recolectar evidencia', description = 'Revisar historial/logs antes de sancionar.' },
        { id = 'resolve_action', title = 'Resolver', description = 'Aplicar accion proporcional y dejar trazabilidad.' }
    },
    high = {
        { id = 'ack', title = 'Acusar recibo urgente', description = 'Responder rapido e iniciar investigacion.' },
        { id = 'freeze_risk', title = 'Contener riesgo', description = 'Aplicar medidas temporales si hay abuso en curso.' },
        { id = 'collect_evidence', title = 'Recolectar evidencia', description = 'Correlacionar logs, detecciones y acciones previas.' },
        { id = 'staff_review', title = 'Revision staff', description = 'Confirmar accion con otro admin si aplica.' },
        { id = 'resolve_action', title = 'Resolver y auditar', description = 'Ejecutar accion final y documentar resultado.' }
    },
    critical = {
        { id = 'ack', title = 'Incidente critico', description = 'Marcar incidente y notificar staff de guardia.' },
        { id = 'containment', title = 'Contencion inmediata', description = 'Bloquear impacto activo (quarantine/kick/ban segun evidencia).' },
        { id = 'evidence_pack', title = 'Evidence pack', description = 'Guardar trazas previas (timeline, eventos, identificadores).' },
        { id = 'dual_review', title = 'Revision dual', description = 'Confirmar accion extrema con segundo admin cuando sea posible.' },
        { id = 'postmortem', title = 'Cierre tecnico', description = 'Registrar causa raiz y acciones de seguimiento.' }
    }
}

local _PriorityKeywords = {
    critical = {
        'crash', 'dupe', 'exploit', 'inject', 'injector', 'executor', 'backdoor',
        'spoof', 'admin event', 'txadmin', 'wipe', 'ddos', 'overflow'
    },
    high = {
        'cheat', 'aimbot', 'triggerbot', 'godmode', 'noclip', 'speedhack',
        'money', 'dinero', 'economia', 'inventario', 'weapon', 'arma'
    },
    medium = {
        'meta', 'toxic', 'insulto', 'spam', 'acoso', 'bug', 'abuso'
    }
}

local function _NormalizePriority(priority)
    local p = tostring(priority or ''):lower():match('^%s*(.-)%s*$')
    if p == 'low' or p == 'medium' or p == 'high' or p == 'critical' then
        return p
    end
    local cfg = Config and Config.ReportPriority or nil
    local def = cfg and tostring(cfg.defaultPriority or ''):lower() or ''
    if def == 'low' or def == 'medium' or def == 'high' or def == 'critical' then
        return def
    end
    return 'medium'
end

local function _AutoPriorityFromReason(reason, targetId)
    local text = tostring(reason or ''):lower()
    local score = 0

    local function addByKeywords(words, points)
        for _, kw in ipairs(words) do
            if text:find(kw, 1, true) then
                score = score + points
            end
        end
    end

    addByKeywords(_PriorityKeywords.medium, 1)
    addByKeywords(_PriorityKeywords.high, 2)
    addByKeywords(_PriorityKeywords.critical, 4)

    if tonumber(targetId) and tonumber(targetId) > 0 then
        score = score + 1
    end
    if #text >= 180 then
        score = score + 1
    end

    if score >= 7 then return 'critical' end
    if score >= 4 then return 'high' end
    if score >= 2 then return 'medium' end
    return 'low'
end

local function _BuildRunbook(report)
    local priority = _NormalizePriority(report and report.priority)
    local steps = _DefaultRunbooks[priority] or _DefaultRunbooks.medium

    local out = {}
    for i = 1, #steps do
        out[i] = {
            order = i,
            id = steps[i].id,
            title = steps[i].title,
            description = steps[i].description
        }
    end

    return {
        version = 1,
        priority = priority,
        reportId = report and tonumber(report.id) or nil,
        steps = out
    }
end

local function _GetResponseTemplates()
    local templates = {}
    local src = Config and Config.ResponseTemplates or nil
    if type(src) == 'table' then
        for i = 1, #src do
            local t = src[i]
            if type(t) == 'table' then
                local id = _SanitizeText(t.id or '', 32):lower()
                local text = _SanitizeText(t.text or '', 240)
                if id ~= '' and text ~= '' then
                    templates[#templates + 1] = { id = id, text = text }
                end
            end
        end
    end
    if #templates == 0 then
        templates = {
            { id = 'investigating', text = 'Estamos revisando tu reporte.' },
            { id = 'resolved', text = 'Tu reporte fue resuelto. Gracias por reportar.' },
            { id = 'need_evidence', text = 'Necesitamos mas evidencia para continuar.' }
        }
    end
    return templates
end

-- 
-- REPORT MANAGEMENT
-- 

--- Create a new report
---@param reporterSource number Source of reporting player
---@param targetId number|nil Target player ID (if reporting a player)
---@param reason string Report reason
---@return boolean success
---@return string|nil reportId
function ReportSystem.CreateReport(reporterSource, targetId, reason)
    if not Settings.enabled then
        return false, 'Sistema de reportes desactivado'
    end
    
    local reporterName = GetPlayerName(reporterSource)
    if not reporterName then
        return false, 'Jugador no valido'
    end
    
    targetId = tonumber(targetId)
    if targetId and targetId <= 0 then
        targetId = nil
    end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    -- Reports can be a bit longer than admin reasons, but still clamp to avoid abuse.
    reasonMax = math.max(reasonMax, 400)
    reason = _SanitizeText(reason or '', reasonMax)
    reason = reason:match('^%s*(.-)%s*$') or reason
    if reason == '' then
        return false, 'Razon invalida'
    end

    -- Check cooldown
    local now = os.time()
    if ReportCooldowns[reporterSource] and (now - ReportCooldowns[reporterSource]) < Settings.cooldownSeconds then
        local remaining = Settings.cooldownSeconds - (now - ReportCooldowns[reporterSource])
        return false, ('Espera %d segundos antes de reportar de nuevo'):format(remaining)
    end
    
    local maxActive = tonumber(Settings.maxActiveReports) or 50
    
    -- Get target info if provided
    local targetName = nil
    if targetId and GetPlayerName(targetId) then
        targetName = GetPlayerName(targetId)
    else
        targetId = nil
    end

    local reporterLicense = GetId(reporterSource, 'license')
    local targetLicense = (targetId and targetId > 0) and GetId(targetId, 'license') or nil

    -- Max active reports check (DB-backed)
    MySQL.scalar("SELECT COUNT(*) FROM lyxpanel_reports WHERE status IN ('open','in_progress')", {}, function(c)
        if (c or 0) >= maxActive then
            if GetPlayerName(reporterSource) then
                TriggerClientEvent('chat:addMessage', reporterSource, {
                    color = { 255, 0, 0 },
                    multiline = true,
                    args = { 'Reporte', 'Cola de reportes llena, intenta mas tarde' }
                })
            end
            return
        end

        ReportCooldowns[reporterSource] = now

        local autoPriority = _AutoPriorityFromReason(reason, targetId)
        local report = {
            reporter_id = reporterLicense or 'unknown',
            reporter_name = reporterName,
            reported_id = targetLicense,
            reported_name = targetName,
            reason = reason,
            priority = autoPriority,
            status = 'open'
        }

        -- Save to database
        ReportSystem.SaveToDatabase(report, function(dbId)
            if GetPlayerName(reporterSource) then
                TriggerClientEvent('chat:addMessage', reporterSource, {
                    color = { 0, 255, 0 },
                    multiline = true,
                    args = { 'Reporte', ('Reporte #%s enviado. Un admin lo revisara pronto.'):format(dbId) }
                })
            end

            report.id = dbId
            report.reporter_source = reporterSource
            report.target_source = targetId
            ReportSystem.NotifyAdmins(report)
            ReportSystem.SendWebhook(report)
        end)
    end)

    return true, 'ok'
end

--- Claim a report
---@param adminSource number Admin source
---@param reportId string Report ID
---@return boolean success
function ReportSystem.ClaimReport(adminSource, reportId)
    if not _IsAdminForReports(adminSource) then
        return false, 'Sin permisos'
    end

    if _IsRateLimited(adminSource, 'reports_claim', _GetCooldownMs('reportsClaim', 750)) then
        return false, 'Rate limit'
    end

    reportId = tonumber(reportId)
    if not reportId or reportId <= 0 then
        return false, 'Reporte no valido'
    end

    local assignedTo = GetId(adminSource, 'license') or GetPlayerName(adminSource) or 'unknown'

    MySQL.update("UPDATE lyxpanel_reports SET status = 'in_progress', assigned_to = ? WHERE id = ? AND status = 'open'",
        { assignedTo, reportId }, function(affected)
            if not affected or affected <= 0 then
                TriggerClientEvent('lyxpanel:notify', adminSource, 'error', 'Reporte no encontrado o ya atendido')
                return
            end

            -- Notify reporter if online
            MySQL.query('SELECT reporter_id FROM lyxpanel_reports WHERE id = ? LIMIT 1', { reportId }, function(rows)
                local rid = rows and rows[1] and rows[1].reporter_id or nil
                local reporterSrc = _FindOnlineByLicense(rid)
                if reporterSrc and GetPlayerName(reporterSrc) then
                    TriggerClientEvent('chat:addMessage', reporterSrc, {
                        color = { 0, 255, 0 },
                        multiline = true,
                        args = { 'Reporte', ('Tu reporte #%s esta siendo atendido por %s'):format(reportId, GetPlayerName(adminSource) or 'admin') }
                    })
                end
            end)

            TriggerClientEvent('lyxpanel:notify', adminSource, 'success', 'Reporte reclamado')
        end)

    return true, 'ok'
end

--- Resolve a report
---@param adminSource number Admin source
---@param reportId string Report ID
---@param resolution string Resolution description
---@return boolean success
function ReportSystem.ResolveReport(adminSource, reportId, resolution)
    if not _IsAdminForReports(adminSource) then
        return false, 'Sin permisos'
    end

    if _IsRateLimited(adminSource, 'reports_resolve', _GetCooldownMs('reportsResolve', 750)) then
        return false, 'Rate limit'
    end

    reportId = tonumber(reportId)
    if not reportId or reportId <= 0 then
        return false, 'Reporte no valido'
    end

    local resMax = math.max(_GetLimitNumber('maxReasonLength', 200), 400)
    resolution = _SanitizeText(resolution or '', resMax)
    resolution = resolution:match('^%s*(.-)%s*$') or resolution
    if resolution == '' then
        resolution = 'Resuelto'
    end

    MySQL.update("UPDATE lyxpanel_reports SET status = 'closed' WHERE id = ? AND status IN ('open','in_progress')",
        { reportId }, function(affected)
            if not affected or affected <= 0 then
                TriggerClientEvent('lyxpanel:notify', adminSource, 'error', 'Reporte no encontrado o ya cerrado')
                return
            end

            -- Notify reporter if online
            MySQL.query('SELECT reporter_id FROM lyxpanel_reports WHERE id = ? LIMIT 1', { reportId }, function(rows)
                local rid = rows and rows[1] and rows[1].reporter_id or nil
                local reporterSrc = _FindOnlineByLicense(rid)
                if reporterSrc and GetPlayerName(reporterSrc) then
                    TriggerClientEvent('chat:addMessage', reporterSrc, {
                        color = { 0, 255, 0 },
                        multiline = true,
                        args = { 'Reporte', ('Tu reporte #%s fue resuelto: %s'):format(reportId, resolution) }
                    })
                end
            end)

            TriggerClientEvent('lyxpanel:notify', adminSource, 'success', 'Reporte resuelto')
        end)

    return true, 'ok'
end

--- Get all pending reports
---@return table reports
function ReportSystem.GetPendingReports()
    -- Deprecated: prefer ESX callbacks in server/main.lua (DB-backed UI).
    -- Kept for compatibility with older clients. This returns a minimal list from DB.
    local rows = MySQL.Sync.fetchAll([[
        SELECT *,
        (
            CASE priority
                WHEN 'critical' THEN 400
                WHEN 'high' THEN 300
                WHEN 'medium' THEN 200
                ELSE 100
            END
            + CASE status WHEN 'open' THEN 35 ELSE 0 END
            + LEAST(TIMESTAMPDIFF(MINUTE, created_at, UTC_TIMESTAMP()), 180)
        ) AS risk_score
        FROM lyxpanel_reports
        WHERE status IN ('open','in_progress')
        ORDER BY risk_score DESC, created_at ASC
        LIMIT 100
    ]], {})
    return rows or {}
end

--- Get prioritized report queue with risk score
---@param limit number|nil
---@return table
function ReportSystem.GetReportQueue(limit)
    limit = tonumber(limit) or 100
    if limit < 1 then limit = 1 end
    if limit > 300 then limit = 300 end

    local rows = MySQL.Sync.fetchAll([[
        SELECT *,
        (
            CASE priority
                WHEN 'critical' THEN 400
                WHEN 'high' THEN 300
                WHEN 'medium' THEN 200
                ELSE 100
            END
            + CASE status WHEN 'open' THEN 35 ELSE 0 END
            + LEAST(TIMESTAMPDIFF(MINUTE, created_at, UTC_TIMESTAMP()), 180)
        ) AS risk_score
        FROM lyxpanel_reports
        WHERE status IN ('open','in_progress')
        ORDER BY risk_score DESC, created_at ASC
        LIMIT ?
    ]], { limit })

    return rows or {}
end

--- Build moderation runbook for a report id
---@param reportId number
---@return table|nil
function ReportSystem.GetRunbook(reportId)
    reportId = tonumber(reportId)
    if not reportId or reportId <= 0 then
        return nil
    end

    local rows = MySQL.Sync.fetchAll('SELECT id, priority, status, reason FROM lyxpanel_reports WHERE id = ? LIMIT 1', { reportId })
    local report = rows and rows[1]
    if not report then
        return nil
    end

    return _BuildRunbook(report)
end

--- Get moderation templates for UI/actions
---@return table
function ReportSystem.GetTemplates()
    return _GetResponseTemplates()
end

--- Notify all admins about a new report
---@param report table
function ReportSystem.NotifyAdmins(report)
    local players = GetPlayers()
    
    for _, playerId in ipairs(players) do
        local source = tonumber(playerId)

        if source and GetPlayerName(source) and _IsAdminForReports(source) then
            local displayId = report.id or 'N/A'
            TriggerClientEvent('chat:addMessage', source, {
                color = {255, 165, 0},
                multiline = true,
                args = {'Nuevo Reporte', ('ID: %s | De: %s | Razon: %s'):format(
                    displayId,
                    report.reporter_name or (report.reporter and report.reporter.name) or 'N/A',
                    report.reason or 'N/A'
                )}
            })

            TriggerClientEvent('lyxpanel:notify', source, 'info',
                ('Nuevo reporte #%s de %s'):format(displayId, report.reporter_name or 'N/A'))
            TriggerClientEvent('lyxpanel:playSound', source, 'report')
        end
    end
end

--- Send report to Discord webhook
---@param report table
function ReportSystem.SendWebhook(report)
    local webhook = Config and Config.Discord and Config.Discord.webhooks and Config.Discord.webhooks.reports or ''
    if not webhook or webhook == '' then return end
    
    local embed = {
        title = 'Nuevo Reporte - ' .. tostring(report.id or 'N/A'),
        color = 16744448, -- Orange
        fields = {
            {
                name = 'Reportado por',
                value = ('%s (ID: %s)'):format(
                    tostring(report.reporter_name or (report.reporter and report.reporter.name) or 'N/A'),
                    tostring(report.reporter_source or (report.reporter and report.reporter.source) or 'N/A')
                ),
                inline = true
            },
            {
                name = 'Razon',
                value = tostring(report.reason or 'N/A'),
                inline = false
            }
        },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        footer = {
            text = 'LyxPanel Report System'
        }
    }
    
    if report.reported_name or report.target then
        table.insert(embed.fields, 2, {
            name = 'Reportado',
            value = ('%s (ID: %s)'):format(
                tostring(report.reported_name or (report.target and report.target.name) or 'N/A'),
                tostring(report.target_source or (report.target and report.target.source) or 'N/A')
            ),
            inline = true
        })
    end
    
    local payload = json.encode({
        embeds = { embed }
    })
    
    PerformHttpRequest(webhook, function() end, 'POST', payload, {
        ['Content-Type'] = 'application/json'
    })
end

-- Save report to database
--@param report table
function ReportSystem.SaveToDatabase(report, cb)
    local reporterId = report.reporter_id or 'unknown'
    local reporterName = report.reporter_name or 'unknown'
    local reportedId = report.reported_id
    local reportedName = report.reported_name
    local status = report.status or 'open'
    local priority = report.priority or 'medium'

    MySQL.insert(
        'INSERT INTO lyxpanel_reports (reporter_id, reporter_name, reported_id, reported_name, reason, priority, status) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { reporterId or 'unknown', reporterName, reportedId, reportedName, report.reason, priority, status },
        function(insertId)
            if type(cb) == 'function' then cb(insertId) end
        end)
end

-- 
-- INITIALIZATION
-- 

--- Initialize report system
function ReportSystem.Init()
    -- Register commands
    RegisterCommand(Settings.reportCommand, function(source, args)
        if source == 0 then return end
        
        local reason = table.concat(args, ' ')
        if reason == '' then
            TriggerClientEvent('chat:addMessage', source, {
                color = {255, 0, 0},
                args = {'Error', ('Uso: /%s [razon]'):format(Settings.reportCommand)}
            })
            return
        end
        
        local success, result = ReportSystem.CreateReport(source, nil, reason)
        
        if not success then
            TriggerClientEvent('chat:addMessage', source, {
                color = {255, 0, 0},
                args = {'Error', result}
            })
        end
    end, false)
    
    print('^2[LyxPanel]^7 Report System initialized')
end

-- Event handlers
RegisterNetEvent('lyxpanel:reports:create')
AddEventHandler('lyxpanel:reports:create', function(targetId, reason)
    local source = source
    -- Basic rate-limit for event spam
    local cdMs = math.max(250, math.floor((tonumber(Settings.cooldownSeconds) or 60) * 1000 / 2))
    if _IsRateLimited(source, 'reports_create_evt', cdMs) then return end

    local ok, msg = ReportSystem.CreateReport(source, targetId, reason)
    if not ok and GetPlayerName(source) then
        TriggerClientEvent('chat:addMessage', source, {
            color = { 255, 0, 0 },
            args = { 'Error', msg or 'No se pudo crear el reporte' }
        })
    end
end)

RegisterNetEvent('lyxpanel:reports:claim')
AddEventHandler('lyxpanel:reports:claim', function(reportId)
    local source = source
    local ok, msg = ReportSystem.ClaimReport(source, reportId)
    if not ok then
        TriggerClientEvent('lyxpanel:notify', source, 'error', msg or 'No se pudo reclamar')
    end
end)

RegisterNetEvent('lyxpanel:reports:resolve')
AddEventHandler('lyxpanel:reports:resolve', function(reportId, resolution)
    local source = source
    local ok, msg = ReportSystem.ResolveReport(source, reportId, resolution)
    if not ok then
        TriggerClientEvent('lyxpanel:notify', source, 'error', msg or 'No se pudo resolver')
    end
end)

RegisterNetEvent('lyxpanel:reports:get')
AddEventHandler('lyxpanel:reports:get', function()
    local source = source
    if not _IsAdminForReports(source) then return end
    if _IsRateLimited(source, 'reports_get', _GetCooldownMs('reportsGet', 1500)) then return end
    local reports = ReportSystem.GetReportQueue(100)
    TriggerClientEvent('lyxpanel:reports:list', source, reports or {})
end)

local function _RegisterEsxCallbacks(esx)
    if not esx then return end

    esx.RegisterServerCallback('lyxpanel:reports:getQueue', function(source, cb, limit)
        if not _IsAdminForReports(source) then
            return cb({ success = false, error = 'no_permission' })
        end
        if _IsRateLimited(source, 'reports_queue_cb', _GetCooldownMs('reportsGet', 1500)) then
            return cb({ success = false, error = 'rate_limited' })
        end
        cb({ success = true, rows = ReportSystem.GetReportQueue(limit or 100) })
    end)

    esx.RegisterServerCallback('lyxpanel:reports:getRunbook', function(source, cb, reportId)
        if not _IsAdminForReports(source) then
            return cb({ success = false, error = 'no_permission' })
        end
        local runbook = ReportSystem.GetRunbook(reportId)
        if not runbook then
            return cb({ success = false, error = 'report_not_found' })
        end
        cb({ success = true, runbook = runbook })
    end)

    esx.RegisterServerCallback('lyxpanel:reports:getTemplates', function(source, cb)
        if not _IsAdminForReports(source) then
            return cb({ success = false, error = 'no_permission' })
        end
        cb({ success = true, templates = ReportSystem.GetTemplates() })
    end)
end

-- Auto-escalate stale open reports according to Config.ReportPriority.autoEscalate
CreateThread(function()
    while true do
        Wait(60000)

        local cfg = Config and Config.ReportPriority or nil
        local auto = cfg and cfg.autoEscalate or nil
        if not auto or auto.enabled ~= true then
            goto continue
        end

        local minutes = tonumber(auto.minutes) or 10
        if minutes < 1 then minutes = 1 end
        if minutes > 720 then minutes = 720 end

        local escalateTo = _NormalizePriority(auto.escalateTo or 'high')
        local toRank = _PriorityRank[escalateTo] or _PriorityRank.high

        local eligible = {}
        for p, rank in pairs(_PriorityRank) do
            if rank < toRank then
                eligible[#eligible + 1] = ("'%s'"):format(p)
            end
        end
        if #eligible == 0 then
            goto continue
        end

        local sql = ([[UPDATE lyxpanel_reports
            SET priority = ?
            WHERE status = 'open'
              AND priority IN (%s)
              AND created_at <= DATE_SUB(UTC_TIMESTAMP(), INTERVAL ? MINUTE)]]):format(table.concat(eligible, ','))

        MySQL.update(sql, { escalateTo, minutes }, function(affected)
            if affected and affected > 0 and Config and Config.Debug then
                print(('[LyxPanel][Reports] Auto-escalated %d report(s) to %s'):format(affected, escalateTo))
            end
        end)

        ::continue::
    end
end)

-- Initialize on start
CreateThread(function()
    local esx = ESX
    if not esx and LyxPanel and LyxPanel.WaitForESX then
        esx = LyxPanel.WaitForESX(15000)
    end
    _RegisterEsxCallbacks(esx)

    Wait(2000)
    ReportSystem.Init()
end)

LyxPanel = LyxPanel or {}
LyxPanel.ReportSystem = ReportSystem

return ReportSystem



