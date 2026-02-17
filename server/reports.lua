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

        local report = {
            reporter_id = reporterLicense or 'unknown',
            reporter_name = reporterName,
            reported_id = targetLicense,
            reported_name = targetName,
            reason = reason,
            priority = 'medium',
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
        SELECT * FROM lyxpanel_reports
        WHERE status IN ('open','in_progress')
        ORDER BY created_at DESC
        LIMIT 100
    ]], {})
    return rows or {}
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
    local reports = ReportSystem.GetPendingReports()
    TriggerClientEvent('lyxpanel:reports:list', source, reports or {})
end)

-- Initialize on start
CreateThread(function()
    Wait(2000)
    ReportSystem.Init()
end)

return ReportSystem



