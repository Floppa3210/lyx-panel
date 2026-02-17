--[[
    
                             LYXPANEL v4.0 - SERVER MAIN                           
                            Optimizado para ESX Legacy 1.9+                        
    
]]

-- Prefer the ESX global provided by @es_extended/imports.lua (fxmanifest shared_scripts).
-- Keep a local reference for speed, but never block forever if ESX isn't available.
local ESX = ESX
local AdminData = {}
local PlayerNotes = {}
local ActivePanelSessions = {}
local _PanelSessionSpoofCooldowns = {}
local _PanelActionSecurityState = {
    sessions = {},
    contexts = {},
}
local _AuditDeniedPermission

local function _NowMs()
    return GetGameTimer()
end

local function _GetPanelSessionTtlMs()
    local fw = Config and Config.Security and Config.Security.adminEventFirewall or nil
    local ttl = fw and tonumber(fw.sessionTtlMs) or 10 * 60 * 1000
    if ttl < 30000 then ttl = 30000 end -- minimum 30s
    return ttl
end

local function _GetPanelActionSecurityCfg()
    local root = Config and Config.Security and Config.Security.adminEventFirewall or nil
    local cfg = root and root.actionSecurity or nil
    local out = {
        enabled = cfg == nil or cfg.enabled ~= false,
        requireForActionEvents = cfg == nil or cfg.requireForActionEvents ~= false,
        requireForProtectedEvents = cfg and cfg.requireForProtectedEvents == true,
        tokenTtlMs = tonumber(cfg and cfg.tokenTtlMs) or (5 * 60 * 1000),
        nonceTtlMs = tonumber(cfg and cfg.nonceTtlMs) or (5 * 60 * 1000),
        maxUsedNonces = tonumber(cfg and cfg.maxUsedNonces) or 4096,
        maxClockSkewMs = tonumber(cfg and cfg.maxClockSkewMs) or 180000,
        contextTtlMs = tonumber(cfg and cfg.contextTtlMs) or 20000,
        tokenMinLen = tonumber(cfg and cfg.tokenMinLen) or 24,
        tokenMaxLen = tonumber(cfg and cfg.tokenMaxLen) or 128,
        nonceMinLen = tonumber(cfg and cfg.nonceMinLen) or 16,
        nonceMaxLen = tonumber(cfg and cfg.nonceMaxLen) or 128,
        correlationMinLen = tonumber(cfg and cfg.correlationMinLen) or 10,
        correlationMaxLen = tonumber(cfg and cfg.correlationMaxLen) or 128,
    }

    if out.tokenTtlMs < 30000 then out.tokenTtlMs = 30000 end
    if out.nonceTtlMs < 15000 then out.nonceTtlMs = 15000 end
    if out.maxUsedNonces < 128 then out.maxUsedNonces = 128 end
    if out.maxClockSkewMs < 10000 then out.maxClockSkewMs = 10000 end
    if out.contextTtlMs < 5000 then out.contextTtlMs = 5000 end

    return out
end

local _PanelRandSeeded = false
local function _EnsurePanelRandomSeed()
    if _PanelRandSeeded then return end
    local base = (os.time() or 0) + (_NowMs() or 0) + math.floor((os.clock() or 0) * 1000)
    math.randomseed(base)
    for _ = 1, 12 do math.random() end
    _PanelRandSeeded = true
end

local function _GenerateSecureId(prefix, bytes)
    _EnsurePanelRandomSeed()
    bytes = tonumber(bytes) or 20
    if bytes < 8 then bytes = 8 end
    if bytes > 48 then bytes = 48 end

    local chunks = {}
    for _ = 1, bytes do
        chunks[#chunks + 1] = string.format('%02x', math.random(0, 255))
    end

    local pre = tostring(prefix or 'id')
    return (pre .. '_' .. table.concat(chunks))
end

local function _GetPanelActionSession(source, createIfMissing)
    source = tonumber(source)
    if not source or source <= 0 then return nil end

    local session = _PanelActionSecurityState.sessions[source]
    if session then
        return session
    end

    if createIfMissing ~= true then
        return nil
    end

    session = {
        token = nil,
        issuedAtMs = 0,
        expiresAtMs = 0,
        consumedNonces = {},
        nonceQueue = {},
        seq = 0,
    }
    _PanelActionSecurityState.sessions[source] = session
    return session
end

local function _CleanupConsumedNonces(session, nowMs, cfg)
    if type(session) ~= 'table' then return end
    if type(session.nonceQueue) ~= 'table' then
        session.nonceQueue = {}
    end
    if type(session.consumedNonces) ~= 'table' then
        session.consumedNonces = {}
    end

    local queue = session.nonceQueue
    local ttl = tonumber(cfg and cfg.nonceTtlMs) or 300000
    local maxNonces = tonumber(cfg and cfg.maxUsedNonces) or 4096

    while #queue > 0 do
        local first = queue[1]
        if type(first) ~= 'table' then
            table.remove(queue, 1)
        else
            local ts = tonumber(first.ts) or 0
            if ts <= 0 or (nowMs - ts) >= ttl or #queue > maxNonces then
                session.consumedNonces[first.nonce] = nil
                table.remove(queue, 1)
            else
                break
            end
        end
    end
end

local function _IssuePanelActionSession(source, forceRenew)
    local cfg = _GetPanelActionSecurityCfg()
    local now = _NowMs()
    local session = _GetPanelActionSession(source, true)
    if not session then
        return nil
    end

    local isExpired = (tonumber(session.expiresAtMs) or 0) <= now
    if forceRenew == true or isExpired or type(session.token) ~= 'string' then
        session.token = _GenerateSecureId('lyxsec', 24)
        session.issuedAtMs = now
        session.expiresAtMs = now + cfg.tokenTtlMs
        session.consumedNonces = {}
        session.nonceQueue = {}
        session.seq = 0
    else
        session.expiresAtMs = math.max(session.expiresAtMs or 0, now + cfg.tokenTtlMs)
    end

    _PanelActionSecurityState.sessions[source] = session
    return {
        enabled = cfg.enabled == true,
        token = session.token,
        tokenTtlMs = cfg.tokenTtlMs,
        nonceTtlMs = cfg.nonceTtlMs,
        maxClockSkewMs = cfg.maxClockSkewMs
    }
end

local function _ExtractSecurityEnvelope(eventData)
    if type(eventData) ~= 'table' then
        return nil
    end
    local argCount = #eventData
    if argCount <= 0 then
        return nil
    end
    local raw = eventData[argCount]
    if type(raw) ~= 'table' then
        return nil
    end
    local sec = raw.__lyxsec
    if type(sec) ~= 'table' then
        return nil
    end
    return sec
end

function ValidatePanelActionEnvelope(source, eventName, eventData, eventRule)
    local cfg = _GetPanelActionSecurityCfg()
    if cfg.enabled ~= true then
        return true, nil, nil
    end

    local isActionEvent = type(eventRule) == 'table' and eventRule.isAction == true
    local requires = false
    if isActionEvent and cfg.requireForActionEvents == true then
        requires = true
    elseif not isActionEvent and cfg.requireForProtectedEvents == true then
        requires = true
    end

    if requires ~= true then
        return true, nil, nil
    end

    local now = _NowMs()
    local session = _GetPanelActionSession(source, false)
    if not session or type(session.token) ~= 'string' or (tonumber(session.expiresAtMs) or 0) <= now then
        return false, 'security_session_missing_or_expired', { event = eventName }
    end

    local sec = _ExtractSecurityEnvelope(eventData)
    if type(sec) ~= 'table' then
        return false, 'security_envelope_missing', { event = eventName }
    end

    local token = tostring(sec.token or '')
    local nonce = tostring(sec.nonce or '')
    local correlationId = tostring(sec.correlation_id or sec.correlationId or '')
    local ts = tonumber(sec.ts) or 0

    if #token < cfg.tokenMinLen or #token > cfg.tokenMaxLen then
        return false, 'security_token_bad_length', { len = #token }
    end
    if token ~= session.token then
        return false, 'security_token_mismatch', { event = eventName }
    end

    if #nonce < cfg.nonceMinLen or #nonce > cfg.nonceMaxLen then
        return false, 'security_nonce_bad_length', { len = #nonce }
    end
    if not nonce:match('^[%w%-%_%.:]+$') then
        return false, 'security_nonce_bad_format', { nonce = nonce:sub(1, 32) }
    end

    if #correlationId < cfg.correlationMinLen or #correlationId > cfg.correlationMaxLen then
        return false, 'security_correlation_bad_length', { len = #correlationId }
    end

    if ts > 0 then
        local serverEpochMs = os.time() * 1000
        if math.abs(serverEpochMs - ts) > cfg.maxClockSkewMs then
            return false, 'security_timestamp_out_of_window', {
                clientTs = ts,
                serverTs = serverEpochMs
            }
        end
    end

    _CleanupConsumedNonces(session, now, cfg)
    if session.consumedNonces[nonce] then
        return false, 'security_nonce_replay', {
            nonce = nonce:sub(1, 32),
            correlation_id = correlationId
        }
    end

    session.seq = (tonumber(session.seq) or 0) + 1
    session.consumedNonces[nonce] = now
    session.nonceQueue[#session.nonceQueue + 1] = { nonce = nonce, ts = now }
    _CleanupConsumedNonces(session, now, cfg)
    _PanelActionSecurityState.sessions[source] = session

    local ctx = {
        source = source,
        event = tostring(eventName or ''),
        nonce = nonce,
        correlation_id = correlationId,
        seq = session.seq,
        ts = now
    }
    _PanelActionSecurityState.contexts[source] = ctx

    return true, nil, ctx
end

local function _GetPanelActionContext(source, eventName)
    source = tonumber(source)
    if not source or source <= 0 then return nil end
    local ctx = _PanelActionSecurityState.contexts[source]
    if type(ctx) ~= 'table' then return nil end

    local ttl = _GetPanelActionSecurityCfg().contextTtlMs
    if (_NowMs() - (tonumber(ctx.ts) or 0)) > ttl then
        _PanelActionSecurityState.contexts[source] = nil
        return nil
    end

    if type(eventName) == 'string' and eventName ~= '' and tostring(ctx.event) ~= eventName then
        return nil
    end
    return ctx
end

function GetPanelActionSecurityForClient(source)
    local cfg = _GetPanelActionSecurityCfg()
    if cfg.enabled ~= true then
        return { enabled = false }
    end
    return _IssuePanelActionSession(source, false) or { enabled = false }
end

local function _GetPanelSessionSpoofConfig()
    local cfg = Config and Config.Security and Config.Security.panelSessionSpoof or {}
    local out = {
        enabled = cfg.enabled == true,
        permaban = cfg.permaban ~= false,
        banDuration = tonumber(cfg.banDuration),
        banReason = tostring(cfg.banReason or 'Cheating detected (panel session spoof)'),
        banBy = tostring(cfg.banBy or 'LyxPanel Security'),
        cooldownMs = tonumber(cfg.cooldownMs) or 15000,
        dropIfGuardMissing = cfg.dropIfGuardMissing ~= false
    }

    if out.banDuration == nil then
        out.banDuration = 0
    end

    if out.cooldownMs < 1000 then
        out.cooldownMs = 1000
    end

    return out
end

local function _ForwardPanelSessionSpoofDetection(src)
    if not Config or not Config.Security or Config.Security.forwardDeniedToLyxGuard ~= true then
        return
    end

    if not exports['lyx-guard'] or not exports['lyx-guard'].LogDetection then
        return
    end

    pcall(function()
        exports['lyx-guard']:LogDetection(src, 'lyxpanel_panel_session_spoof', {
            reason = 'non_admin_panel_session_open'
        }, nil, 'high')
    end)
end

local function _HandlePanelSessionSpoof(src)
    local cfg = _GetPanelSessionSpoofConfig()
    if cfg.enabled ~= true then
        return
    end

    local now = GetGameTimer()
    local last = tonumber(_PanelSessionSpoofCooldowns[src]) or 0
    if (now - last) < cfg.cooldownMs then
        return
    end
    _PanelSessionSpoofCooldowns[src] = now

    _AuditDeniedPermission(src, 'panelSession', nil, 'panel_session_spoof')
    _ForwardPanelSessionSpoofDetection(src)

    local punished = false
    if cfg.permaban then
        if exports['lyx-guard'] and exports['lyx-guard'].BanPlayer then
            local ok, res = pcall(function()
                return exports['lyx-guard']:BanPlayer(src, cfg.banReason, cfg.banDuration, cfg.banBy)
            end)
            punished = ok and res ~= false
        end

        if not punished and cfg.dropIfGuardMissing then
            DropPlayer(src, 'LyxPanel Security: ' .. cfg.banReason)
        end
    elseif cfg.dropIfGuardMissing then
        DropPlayer(src, 'LyxPanel Security: unauthorized panel session')
    end
end

function TouchPanelSession(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    if not GetPlayerName(source) then return false end
    ActivePanelSessions[source] = _NowMs()
    local secCfg = _GetPanelActionSecurityCfg()
    if secCfg.enabled == true then
        _IssuePanelActionSession(source, false)
    end
    return true
end

function IsPanelSessionActive(source, ttlMs)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    local last = tonumber(ActivePanelSessions[source]) or 0
    if last <= 0 then return false end
    local ttl = tonumber(ttlMs) or _GetPanelSessionTtlMs()
    return (_NowMs() - last) <= ttl
end

local function DebugPrint(...)
    if Config and Config.Debug then
        print(...)
    end
end

-- ---------------------------------------------------------------------------
-- SECURITY AUDIT (log denied permission usage, rate-limited)
-- ---------------------------------------------------------------------------

local _DeniedPermCooldowns = {}

local function _IsDeniedRateLimited(src, key, cooldownMs)
    if not src or src <= 0 then return true end

    local now = GetGameTimer()
    _DeniedPermCooldowns[src] = _DeniedPermCooldowns[src] or {}
    local last = _DeniedPermCooldowns[src][key] or 0

    if (now - last) < (cooldownMs or 0) then
        return true
    end

    _DeniedPermCooldowns[src][key] = now
    return false
end

_AuditDeniedPermission = function(src, perm, group, reason)
    if not Config or not Config.Security or Config.Security.logDeniedPermissions ~= true then
        return
    end

    local cooldownMs = tonumber(Config.Security.deniedCooldownMs) or 5000
    local key = tostring(perm or 'unknown')
    if _IsDeniedRateLimited(src, key, cooldownMs) then
        return
    end

    local playerName = GetPlayerName(src) or 'unknown'
    local adminIdentifier = 'unknown'
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if string.find(id, 'license:') then
            adminIdentifier = id
            break
        end
    end

    print(('[LyxPanel][SECURITY] Denied permission: %s | player=%s (%d) | group=%s | reason=%s'):format(
        tostring(perm),
        playerName,
        src,
        tostring(group or 'none'),
        tostring(reason or 'denied')
    ))

    -- Persist denied permission attempts to admin logs for panel auditing/debugging.
    if MySQL and MySQL.insert then
        pcall(function()
            MySQL.insert([[
                INSERT INTO lyxpanel_logs (admin_id, admin_name, action, target_id, target_name, details)
                VALUES (?, ?, ?, ?, ?, ?)
            ]], {
                adminIdentifier,
                playerName,
                'DENIED_PERMISSION',
                tostring(src),
                playerName,
                json.encode({
                    permission = tostring(perm or 'unknown'),
                    group = tostring(group or 'none'),
                    reason = tostring(reason or 'denied')
                })
            })
        end)
    end

    if GetResourceState('lyx-guard') == 'started' and exports['lyx-guard'] and exports['lyx-guard'].PushExhaustiveLog then
        pcall(function()
            exports['lyx-guard']:PushExhaustiveLog({
                level = 'warn',
                actor_type = 'admin',
                actor_id = adminIdentifier,
                actor_name = playerName,
                target_id = tostring(src),
                target_name = playerName,
                resource = 'lyx-panel',
                action = 'DENIED_PERMISSION',
                result = 'blocked',
                reason = tostring(reason or 'denied'),
                metadata = {
                    permission = tostring(perm or 'unknown'),
                    group = tostring(group or 'none')
                }
            })
        end)
    end

    if Config.Security.forwardDeniedToLyxGuard == true and
        GetResourceState('lyx-guard') == 'started' and
        exports['lyx-guard'] and exports['lyx-guard'].LogDetection then
        pcall(function()
            exports['lyx-guard']:LogDetection(src, 'lyxpanel_denied_permission', {
                perm = tostring(perm),
                group = tostring(group or 'none'),
                reason = tostring(reason or 'denied')
            }, nil, 'flagged')
        end)
    end
end

-- 
-- UTILIDADES COMUNES
-- 

local function GetIdentifier(source, idType)
    idType = idType or 'license'
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, idType .. ':') then
            return id
        end
    end
    return nil
end

-- Compatibility helper (used by some server modules like actions_extended.lua)
function GetId(source, idType)
    return GetIdentifier(source, idType) or 'unknown'
end

-- 
-- PERMISOS
-- 

function HasPanelAccess(source)
    if not source or source <= 0 then return false, nil end

    -- 
    -- v4.4: PRIORITY 1 - MASTER WHITELIST (Owners del servidor)
    -- Estos jugadores tienen acceso TOTAL sin importar su grupo ESX
    -- 
    local masterConfig = Config.Permissions and Config.Permissions.masterWhitelist
    if masterConfig and masterConfig.enabled then
        local playerIds = GetPlayerIdentifiers(source)
        if playerIds and masterConfig.masters then
            for _, playerId in ipairs(playerIds) do
                for _, masterId in ipairs(masterConfig.masters) do
                    if playerId == masterId then
                        return true, 'master' -- Acceso total como master
                    end
                end
            end
        end
    end

    -- 
    -- PRIORITY 2 - ACE permissions (txAdmin y consola)
    -- 
    local aceRoles = Config.Permissions and Config.Permissions.aceRolePermissions or {}
    for _, entry in ipairs(aceRoles) do
        if entry and entry.ace and entry.group and IsPlayerAceAllowed(source, entry.ace) then
            return true, entry.group
        end
    end

    if IsPlayerAceAllowed(source, 'lyxpanel.admin') then
        return true, 'superadmin'
    end

    if IsPlayerAceAllowed(source, 'lyxpanel.access') then
        return true, 'admin'
    end

    -- Verificar permisos ACE configurables
    local acePerms = Config.Permissions and Config.Permissions.acePermissions or {}
    for _, p in ipairs(acePerms) do
        if IsPlayerAceAllowed(source, p) then
            if p == 'lyxpanel.admin' then
                return true, 'superadmin'
            end
            return true, 'admin'
        end
    end

    -- -----------------------------------------------------------------------
    -- PRIORITY 2.5 - DB Access List (optional)
    -- Allows masters/owners to grant panel access without editing files.
    -- -----------------------------------------------------------------------
    local accessCfg = Config and Config.Permissions and Config.Permissions.accessList
    if accessCfg == nil or accessCfg.enabled ~= false then
        local identifier = GetIdentifier(source, 'license')
        if identifier and LyxPanel and LyxPanel.AccessStore and LyxPanel.AccessStore.GetGroup then
            local dbGroup = LyxPanel.AccessStore.GetGroup(identifier)
            if dbGroup and dbGroup ~= '' then
                return true, dbGroup
            end
        end
    end

    -- 
    -- PRIORITY 3 - ESX Group (solo si ESX est disponible)
    -- 
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local group = xPlayer.getGroup()

            -- v4.4: Verificar si es un grupo master
            if masterConfig and masterConfig.masterGroups then
                for _, masterGroup in ipairs(masterConfig.masterGroups) do
                    if group == masterGroup then
                        return true, 'master'
                    end
                end
            end

            -- Verificar grupos permitidos
            local allowedGroups = Config.Permissions and Config.Permissions.allowedGroups or
                { 'superadmin', 'admin', 'mod', 'master', 'owner' }
            for _, g in ipairs(allowedGroups) do
                if group == g then return true, group end
            end
        end
    end

    return false, nil
end

function HasPermission(source, perm)
    local access, group = HasPanelAccess(source)
    if not access then
        _AuditDeniedPermission(source, perm, group, 'no_access')
        return false
    end

    -- Grupos con acceso total - siempre tienen permiso
    local fullAccessGroups = { superadmin = true, master = true, owner = true }
    if fullAccessGroups[group] then
        return true
    end

    -- Verificar permisos especficos del rol
    local identifier = GetIdentifier(source, 'license') or 'unknown'

    -- PRIORITY 1: Individual overrides (DB-backed)
    local indCfg = Config and Config.Permissions and Config.Permissions.individualPermissions
    if indCfg and indCfg.enabled == true and identifier ~= 'unknown' and LyxPanel and LyxPanel.PermissionsStore then
        local ovr = LyxPanel.PermissionsStore.GetIndividualOverride(identifier)
        if ovr and ovr[perm] ~= nil then
            if ovr[perm] == true then
                return true
            end
            _AuditDeniedPermission(source, perm, group, 'individual_override_denied')
            return false
        end
    end

    -- PRIORITY 2: Role permissions (Config + optional DB overrides)
    local perms = Config and Config.Permissions and Config.Permissions.rolePermissions and Config.Permissions.rolePermissions[group]
    if perms then
        local allowed = perms[perm] == true

        if LyxPanel and LyxPanel.PermissionsStore then
            local roleOvr = LyxPanel.PermissionsStore.GetRoleOverride(group)
            if roleOvr and type(roleOvr.perms) == 'table' and roleOvr.perms[perm] ~= nil then
                allowed = roleOvr.perms[perm] == true
            end
        end

        if allowed then
            return true
        end

        _AuditDeniedPermission(source, perm, group, 'missing_permission')
        return false
    end

    _AuditDeniedPermission(source, perm, group, 'unknown_group')
    return false
end

local function _ResolveSourceFromIdentifier(identifier)
    if type(identifier) ~= 'string' or identifier == '' or identifier == 'unknown' then
        return nil
    end

    for _, p in ipairs(GetPlayers()) do
        local src = tonumber(p)
        if src and src > 0 then
            local license = GetIdentifier(src, 'license')
            if license == identifier then
                return src
            end
        end
    end

    return nil
end

function LogAction(adminId, adminName, action, targetId, targetName, details)
    local payload = details
    if type(payload) ~= 'table' then
        payload = { value = details }
    end

    local sourceHint = tonumber(payload._adminSource)
    if not sourceHint or sourceHint <= 0 then
        sourceHint = _ResolveSourceFromIdentifier(tostring(adminId or ''))
    end

    local ctx = nil
    if sourceHint and sourceHint > 0 then
        ctx = _GetPanelActionContext(sourceHint, nil)
    end

    payload.level = tostring(payload.level or 'info')
    payload.result = tostring(payload.result or 'ok')
    payload.event = payload.event or (ctx and ctx.event) or nil
    payload.correlation_id = payload.correlation_id or (ctx and ctx.correlation_id) or nil
    payload.trace = payload.trace or {}
    if type(payload.trace) ~= 'table' then
        payload.trace = { value = tostring(payload.trace) }
    end
    if ctx then
        payload.trace.nonce = payload.trace.nonce or ctx.nonce
        payload.trace.seq = payload.trace.seq or ctx.seq
    end
    payload.trace.action = payload.trace.action or tostring(action or 'UNKNOWN')
    payload.trace.admin_name = payload.trace.admin_name or tostring(adminName or 'unknown')
    payload.trace.target_id = payload.trace.target_id or tostring(targetId or '')
    payload.trace.target_name = payload.trace.target_name or tostring(targetName or '')
    payload.trace.timestamp = payload.trace.timestamp or os.date('%Y-%m-%d %H:%M:%S')

    if GetResourceState('lyx-guard') == 'started' and exports['lyx-guard'] and exports['lyx-guard'].PushExhaustiveLog then
        pcall(function()
            exports['lyx-guard']:PushExhaustiveLog({
                level = payload.level or 'info',
                correlation_id = payload.correlation_id,
                actor_type = 'admin',
                actor_id = tostring(adminId or ''),
                actor_name = tostring(adminName or 'unknown'),
                target_id = tostring(targetId or ''),
                target_name = tostring(targetName or ''),
                resource = 'lyx-panel',
                action = tostring(action or 'UNKNOWN'),
                event = payload.event,
                result = tostring(payload.result or 'ok'),
                reason = tostring(payload.reason or ''),
                metadata = payload
            })
        end)
    end

    MySQL.insert(
        'INSERT INTO lyxpanel_logs (admin_id, admin_name, action, target_id, target_name, details) VALUES (?, ?, ?, ?, ?, ?)',
        { adminId, adminName, action, targetId, targetName, json.encode(payload) })
end

-- 
-- INICIALIZACIN DE BASE DE DATOS
-- 

MySQL.ready(function()
    print('^5[LyxPanel v4.0]^7 Iniciando...') -- startup
    -- Versioned migrations (schema_version)
    if LyxPanel and LyxPanel.Migrations and LyxPanel.Migrations.Apply then
        local ok = LyxPanel.Migrations.Apply()
        if not ok then
            print('^1[LyxPanel v4.0]^7 Error aplicando migraciones. Revisa oxmysql/MySQL.')
        end
    else
        print('^1[LyxPanel v4.0]^7 Migrations module missing - DB init skipped.')
    end

    -- Cache permission overrides from DB (optional)
    if LyxPanel and LyxPanel.PermissionsStore and LyxPanel.PermissionsStore.Reload then
        pcall(function() LyxPanel.PermissionsStore.Reload() end)
    end

    -- Cache access list (optional)
    if LyxPanel and LyxPanel.AccessStore and LyxPanel.AccessStore.Reload then
        pcall(function() LyxPanel.AccessStore.Reload() end)
    end

    print('^2[LyxPanel v4.0]^7 Tablas verificadas (migrations)')

    -- v4.4 FIX: Detectar vehiculos en un thread separado (la funcin se define ms abajo)
    CreateThread(function()
        Wait(2000) -- Esperar a que todo est cargado
        if DetectCustomVehicles then
            DetectCustomVehicles()
        else
            print('^1[LyxPanel ERROR]^7 DetectCustomVehicles no est definida')
        end
    end)
end)

-- 
-- DETECCIN DE VEHCULOS PERSONALIZADOS (v4.1 - Enhanced)
-- 

-- Lista de vehiculos personalizados detectados
local DetectedCustomVehicles = {}

-- 
-- HELPER: Parse vehicles.meta XML to extract model names
-- FIXED: Using LoadResourceFile instead of io.open (FiveM specific)
-- 
local function ParseVehiclesMetaContent(content)
    local vehicles = {}

    if not content or content == "" then return vehicles end

    -- Extract all <modelName> tags from vehicles.meta
    -- Pattern 1: <modelName>vehiclename</modelName>
    for modelName in string.gmatch(content, "<modelName>([^<]+)</modelName>") do
        local cleanName = modelName:match("^%s*(.-)%s*$") -- Trim whitespace
        if cleanName and cleanName ~= "" then
            table.insert(vehicles, cleanName:lower())
        end
    end

    -- Pattern 2: <modelName value="vehiclename"/>
    for modelName in string.gmatch(content, '<modelName%s+value%s*=%s*"([^"]+)"') do
        local cleanName = modelName:match("^%s*(.-)%s*$")
        if cleanName and cleanName ~= "" then
            table.insert(vehicles, cleanName:lower())
        end
    end

    -- Pattern 3: Case insensitive (some metas use MODELNAME or ModelName)
    for modelName in string.gmatch(content:lower(), "<modelname>([^<]+)</modelname>") do
        local cleanName = modelName:match("^%s*(.-)%s*$")
        if cleanName and cleanName ~= "" and not vehicles[cleanName] then
            -- Check if not already added
            local found = false
            for _, v in ipairs(vehicles) do
                if v == cleanName then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(vehicles, cleanName)
            end
        end
    end

    return vehicles
end

--
-- HELPER: Scan resource for vehicles.meta files using LoadResourceFile
-- plus recursive best-effort discovery for nested custom packs.
--
local function _NormalizeMetaPath(path)
    if type(path) ~= 'string' then return nil end
    path = path:gsub('\\', '/')
    path = path:gsub('^%./', '')
    path = path:gsub('^/+', '')
    path = path:gsub('/+', '/')
    if path == '' then return nil end
    return path
end

local function _ExtractManifestMetaPaths(manifest)
    local out = {}
    if type(manifest) ~= 'string' or manifest == '' then
        return out
    end

    local function add(path)
        path = _NormalizeMetaPath(path)
        if not path then return end
        local low = path:lower()
        if low:find('vehicles.meta', 1, true) or low:find('_vehicles.meta', 1, true) then
            out[path] = true
        end
    end

    -- Explicit VEHICLE_METADATA_FILE entries.
    for metaPath in string.gmatch(manifest, "data_file%s*'VEHICLE_METADATA_FILE'%s*'([^']+)'") do add(metaPath) end
    for metaPath in string.gmatch(manifest, 'data_file%s*"VEHICLE_METADATA_FILE"%s*"([^"]+)"') do add(metaPath) end
    for metaPath in string.gmatch(manifest, "data_file%s*'VEHICLE_METADATA_FILE'%s*\"([^\"]+)\"") do add(metaPath) end
    for metaPath in string.gmatch(manifest, "data_file%s*\"VEHICLE_METADATA_FILE\"%s*'([^']+)'") do add(metaPath) end

    -- Generic quoted paths from files/fileset blocks.
    for path in string.gmatch(manifest, "'([^']+)'") do add(path) end
    for path in string.gmatch(manifest, '"([^"]+)"') do add(path) end

    return out
end

local function _ListMetaFilesRecursive(resourcePath)
    local out = {}
    local root = _NormalizeMetaPath(resourcePath)
    if not root then return out end
    if type(io) ~= 'table' or type(io.popen) ~= 'function' then
        return out
    end

    local function normalizeAbs(abs)
        if type(abs) ~= 'string' or abs == '' then return nil end
        abs = abs:gsub('\\', '/')
        abs = abs:gsub('^%s+', ''):gsub('%s+$', '')
        if abs == '' then return nil end
        return abs
    end

    local function addAbsolute(absPath)
        local abs = normalizeAbs(absPath)
        if not abs then return end
        local lowAbs = abs:lower()
        if not lowAbs:find('vehicles.meta', 1, true) and not lowAbs:find('_vehicles.meta', 1, true) then
            return
        end

        local rootNorm = root:gsub('\\', '/')
        local rel = nil
        if lowAbs:sub(1, #rootNorm) == rootNorm:lower() then
            rel = abs:sub(#rootNorm + 1)
        end
        rel = _NormalizeMetaPath(rel)
        if rel then
            out[rel] = true
        end
    end

    local isWindows = tostring(resourcePath):find('\\', 1, true) ~= nil or tostring(resourcePath):match('^%a:[/\\]') ~= nil
    if not isWindows and package and package.config and package.config:sub(1, 1) == '\\' then
        isWindows = true
    end
    local cmd = nil

    if isWindows then
        local escaped = tostring(resourcePath):gsub('"', '')
        cmd = ('cmd /c dir /b /s "%s\\*vehicles.meta" 2>nul'):format(escaped)
    else
        local escaped = tostring(resourcePath):gsub("'", [['"'"']])
        cmd = ("find '%s' -type f \\( -iname 'vehicles.meta' -o -iname '*_vehicles.meta' \\) 2>/dev/null"):format(escaped)
    end

    local pipe = io.popen(cmd)
    if not pipe then
        return out
    end

    for line in pipe:lines() do
        addAbsolute(line)
    end
    pipe:close()

    return out
end

local function ScanResourceForVehicles(resourcePath, resourceName)
    local vehicles = {}
    if not resourcePath or not resourceName then return vehicles end

    local vehicleSet = {}
    local scannedMetaPaths = {}
    local foundVehicles = false

    local function _LoadMetaPath(metaPath)
        metaPath = _NormalizeMetaPath(metaPath)
        if not metaPath or scannedMetaPaths[metaPath] then
            return
        end
        scannedMetaPaths[metaPath] = true

        local content = LoadResourceFile(resourceName, metaPath)
        if not content or content == '' then
            return
        end

        local parsed = ParseVehiclesMetaContent(content)
        if #parsed > 0 then
            foundVehicles = true
            for _, veh in ipairs(parsed) do
                if not vehicleSet[veh] then
                    vehicleSet[veh] = true
                    table.insert(vehicles, veh)
                end
            end

            if Config.Debug then
                print(('[LyxPanel] Found %d vehicles in %s/%s'):format(#parsed, resourceName, metaPath))
            end
        end
    end

    -- Common fallback paths.
    local metaLocations = {
        'vehicles.meta',
        'stream/vehicles.meta',
        'data/vehicles.meta',
        'meta/vehicles.meta',
        '__resource/vehicles.meta',
        '[stream]/vehicles.meta',
        'stream/' .. resourceName .. '/vehicles.meta',
        resourceName .. '_vehicles.meta'
    }
    for _, location in ipairs(metaLocations) do
        _LoadMetaPath(location)
    end

    -- Manifest-driven paths (supports deeply nested files declared in files/data_file).
    local manifest = LoadResourceFile(resourceName, 'fxmanifest.lua')
    if not manifest then
        manifest = LoadResourceFile(resourceName, '__resource.lua')
    end
    local manifestPaths = _ExtractManifestMetaPaths(manifest)
    for path, _ in pairs(manifestPaths) do
        if not path:find('%*', 1, true) then
            _LoadMetaPath(path)
        end
    end

    -- Recursive FS fallback for wildcard manifests and complex packs in subfolders.
    -- Best-effort only: if io.popen is restricted, scanner still uses manifest + common paths.
    if not foundVehicles then
        local discovered = _ListMetaFilesRecursive(resourcePath)
        for relPath, _ in pairs(discovered) do
            _LoadMetaPath(relPath)
        end
    else
        -- Still include extra nested metas not referenced in manifest.
        local discovered = _ListMetaFilesRecursive(resourcePath)
        for relPath, _ in pairs(discovered) do
            _LoadMetaPath(relPath)
        end
    end

    return vehicles
end

-- 
-- MAIN: Detect all custom vehicles from resources
-- v4.4 HOTFIX: SOLO escanea carpeta [cars], NO detecta mapeos ni scripts
-- 
function DetectCustomVehicles()
    print('^5[LyxPanel v4.4]^7  Detectando vehiculos personalizados desde [cars]...')

    local numResources = GetNumResources()
    local customVehicles = {}
    local vehicleSet = {} -- Track unique vehicles

    -- v4.4: ESTRICTOS FILTROS - EXCLUIR TODO LO QUE NO ES VEHICULO
    local excludePatterns = {
        -- Mapeos y MLOs
        'mlo', 'mapping', 'map_', 'maps_', 'interior', 'ymap', 'ytyp',
        '_map', 'fivem-map', 'gabz', 'breze', 'ultramlo', 'k4mb1', 'nopixel',
        'maphome', 'maphouse', 'house_', 'building', 'location', 'place',

        -- Scripts y sistemas
        'script', 'system', 'core', 'framework', 'esx_', 'qb-', 'ox_',
        'es_extended', 'mysql', 'oxmysql', 'basic', 'rcore', 'monitor',
        'chat', 'hardcap', 'session', 'spawnmanager', 'loadingscreen',

        -- Otros recursos NO vehiculos
        'phone', 'inventory', 'bank', 'job_', 'jobs_', 'police', 'ambulance',
        'mechanic', 'shop', 'store', 'menu', 'target', 'interact', 'hud',
        'clothing', 'skin', 'ped_', 'peds_', 'weapon_', 'weapons_',
        'prop_', 'props_', 'furniture', 'object', 'npcs', 'npc_',

        -- Tipos de archivo/recursos no vehiculos
        'sounds', 'audio', 'texture', 'timecycle', 'water', 'popgroups',
        'scenarios', 'ped_', 'cargenmod'
    }

    -- v4.4: SOLO palabras clave que identifican VEHICULOS
    local vehiclePatterns = {
        'car', 'cars', 'vehicle', 'vehicles', 'auto', 'autos', 'carro',
        'carros', 'coche', 'coches', 'moto', 'motos', 'bike', 'truck',
        'suv', 'sedan', 'coupe', 'hatch', 'drift', 'jdm', 'tuner',
        'super', 'sport', 'muscle', 'classic', 'luxury', 'addon',
        'dlc', 'add-on', 'replace', 'pack', 'collection'
    }

    local resourcesScanned = 0
    local resourcesWithVehicles = 0
    local vehiclesFound = 0

    for i = 0, numResources - 1 do
        local resourceName = GetResourceByFindIndex(i)
        if resourceName then
            local resourcePath = GetResourcePath(resourceName)
            local state = GetResourceState(resourceName)
            local nameLower = resourceName:lower()

            -- Solo procesar recursos iniciados
            if state == 'started' or state == 'starting' then
                -- v4.4: FILTRO 1 - Verificar si el recurso esta en carpeta [cars]
                local isInCarsFolder = false
                if resourcePath then
                    local pathLower = resourcePath:lower()
                    -- Buscar si el path contiene [cars] o variantes
                    if pathLower:find('%[cars%]') or
                        pathLower:find('%[vehicles%]') or
                        pathLower:find('%[autos%]') or
                        pathLower:find('%[coches%]') or
                        pathLower:find('%[carros%]') or
                        pathLower:find('/cars/') or
                        pathLower:find('/vehicles/') or
                        pathLower:find('\\cars\\') or
                        pathLower:find('\\vehicles\\') then
                        isInCarsFolder = true
                    end
                end

                -- v4.4: FILTRO 2 - Excluir todo lo que NO sea vehiculo
                local isExcluded = false
                for _, exclude in ipairs(excludePatterns) do
                    if nameLower:find(exclude, 1, true) then
                        isExcluded = true
                        break
                    end
                end

                -- v4.4: FILTRO 3 - Si no esta en [cars], verificar que parezca un vehiculo
                local looksLikeVehicle = false
                if not isInCarsFolder then
                    for _, pattern in ipairs(vehiclePatterns) do
                        if nameLower:find(pattern, 1, true) then
                            looksLikeVehicle = true
                            break
                        end
                    end
                end

                -- v4.4: PROCESAR solo si: esta en [cars] O parece vehiculo Y NO est excluido
                local shouldScan = (isInCarsFolder or looksLikeVehicle) and not isExcluded

                if shouldScan then
                    resourcesScanned = resourcesScanned + 1

                    -- Parse vehicles from this resource - SOLO si tiene vehicles.meta
                    local foundVehicles = ScanResourceForVehicles(resourcePath, resourceName)

                    -- v4.4: SOLO agregar si encontr vehicles.meta REALES (no usar nombre como fallback)
                    if #foundVehicles > 0 then
                        -- Verificar que realmente son spawns de vehiculos
                        local validVehicles = {}
                        for _, spawnName in ipairs(foundVehicles) do
                            local spawnLower = spawnName:lower()

                            -- Excluir si el spawn parece un prop/objeto/trailer genrico
                            local isValidSpawn = true
                            local invalidSpawnPatterns = {
                                'prop_', 'trailer', 'tr_', '_tr', 'tank', 'turret',
                                'barrel', 'door', 'wheel', 'seat', 'engine', 'part',
                                'frame', 'body', 'panel', 'bumper', 'mirror', 'light'
                            }
                            for _, invalid in ipairs(invalidSpawnPatterns) do
                                if spawnLower:find(invalid, 1, true) and not spawnLower:find('car') then
                                    isValidSpawn = false
                                    break
                                end
                            end

                            if isValidSpawn and not vehicleSet[spawnLower] then
                                vehicleSet[spawnLower] = true
                                vehiclesFound = vehiclesFound + 1

                                -- Create display name
                                local displayName = spawnName
                                    :gsub("_", " ")
                                    :gsub("-", " ")
                                    :gsub("(%a)([%w']*)", function(first, rest)
                                        return first:upper() .. rest:lower()
                                    end)

                                table.insert(customVehicles, {
                                    name = spawnName,
                                    label = displayName,
                                    resource = resourceName
                                })
                                table.insert(validVehicles, spawnName)
                            end
                        end

                        if #validVehicles > 0 then
                            resourcesWithVehicles = resourcesWithVehicles + 1
                        end
                    end
                end
            end
        end
    end

    -- Ordenar alfabticamente por label
    table.sort(customVehicles, function(a, b) return a.label < b.label end)

    DetectedCustomVehicles = customVehicles
    print(('^2[LyxPanel v4.4]^7 Escaneados %d recursos, %d con vehiculos, %d vehiculos nicos'):format(
        resourcesScanned, resourcesWithVehicles, vehiclesFound))

    -- Agregar vehiculos configurados manualmente
    if Config.CustomVehicles and #Config.CustomVehicles > 0 then
        for _, v in ipairs(Config.CustomVehicles) do
            local spawnLower = v.name:lower()
            if not vehicleSet[spawnLower] then
                vehicleSet[spawnLower] = true
                table.insert(DetectedCustomVehicles, {
                    name = v.name,
                    label = v.label or v.name,
                    resource = "manual"
                })
            end
        end
        table.sort(DetectedCustomVehicles, function(a, b) return a.label < b.label end)
        print(('^2[LyxPanel v4.4]^7 + %d vehiculos configurados manualmente'):format(#Config.CustomVehicles))
    end

    print(('^2[LyxPanel v4.4]^7  Total: %d vehiculos personalizados disponibles'):format(#DetectedCustomVehicles))
end

-- Funcin para obtener vehiculos personalizados
function GetCustomVehicles()
    return DetectedCustomVehicles
end

-- Comando para re-escanear vehiculos en caliente
RegisterCommand('lyxpanel_rescan', function(source)
    if source == 0 or HasPanelAccess(source) then
        DetectCustomVehicles()
        if source > 0 then
            TriggerClientEvent('lyxpanel:notify', source, 'success',
                'Vehiculos re-escaneados: ' .. #DetectedCustomVehicles .. ' encontrados')
        end
    end
end, true)

-- Console-only bootstrap: seed the DB access list without editing cfg/json.
-- Usage: lyxpanel_seed_access license:xxxx master mi_nota
RegisterCommand('lyxpanel_seed_access', function(source, args, raw)
    if source ~= 0 then
        print('^1[LyxPanel]^7 lyxpanel_seed_access solo puede usarse desde la consola del servidor.')
        return
    end

    local identifier = tostring(args[1] or ''):gsub('%s+', '')
    local groupName = tostring(args[2] or ''):gsub('%s+', '')
    local note = ''
    if #args >= 3 then
        note = table.concat(args, ' ', 3)
    end

    if identifier == '' or groupName == '' then
        print('^3[LyxPanel]^7 Uso: lyxpanel_seed_access license:xxxx master "nota"')
        return
    end

    local allowed = { owner = true, master = true, superadmin = true, admin = true, mod = true, helper = true, moderator = true }
    if not allowed[groupName] then
        print('^1[LyxPanel]^7 Grupo invalido. Permitidos: owner/master/superadmin/admin/mod/helper/moderator')
        return
    end

    if not (LyxPanel and LyxPanel.AccessStore and LyxPanel.AccessStore.Set) then
        print('^1[LyxPanel]^7 AccessStore no disponible.')
        return
    end

    local ok, err = LyxPanel.AccessStore.Set(identifier, groupName, note, 'console', 'console')
    if not ok then
        print(('^1[LyxPanel]^7 No se pudo guardar access_list: %s'):format(tostring(err)))
        return
    end

    if LyxPanel.AccessStore.Reload then
        pcall(function() LyxPanel.AccessStore.Reload() end)
    end

    print(('^2[LyxPanel]^7 Seed access OK: %s => %s'):format(identifier, groupName))
end, true)
-- Exportar la funcin
exports('GetCustomVehicles', GetCustomVehicles)

-- 
-- ESX CALLBACKS (Registered after ESX is ready)
-- 


CreateThread(function()
    local resolved = ESX
    if LyxPanel and LyxPanel.WaitForESX then
        resolved = LyxPanel.WaitForESX(15000)
    end

    if not resolved then
        print('^1[LyxPanel]^7 ESX no disponible (timeout). Callbacks no registrados.')
        return
    end

    ESX = resolved
    _G.ESX = _G.ESX or resolved

    ESX.RegisterServerCallback('lyxpanel:checkAccess', function(source, cb)
        DebugPrint('[LyxPanel] checkAccess solicitado por:', source)
        if not Config then
            print('[LyxPanel] ERROR CRTICO: Config es nil!')
            cb({ access = false })
            return
        end

        local access, group = HasPanelAccess(source)
        DebugPrint('[LyxPanel] HasPanelAccess resultado:', access, group)

        if access then
            TouchPanelSession(source)
            local effective = {}
            local base = (Config.Permissions and Config.Permissions.rolePermissions and Config.Permissions.rolePermissions[group]) or {}
            for k, v in pairs(base) do effective[k] = v end

            if LyxPanel and LyxPanel.PermissionsStore then
                local roleOvr = LyxPanel.PermissionsStore.GetRoleOverride(group)
                if roleOvr and type(roleOvr.perms) == 'table' then
                    for k, v in pairs(roleOvr.perms) do
                        effective[k] = v
                    end
                end

                local identifier = GetIdentifier(source, 'license') or 'unknown'
                local indCfg = Config and Config.Permissions and Config.Permissions.individualPermissions
                if indCfg and indCfg.enabled == true and identifier ~= 'unknown' then
                    local ind = LyxPanel.PermissionsStore.GetIndividualOverride(identifier)
                    if type(ind) == 'table' then
                        for k, v in pairs(ind) do
                            effective[k] = v
                        end
                    end
                end
            end

            DebugPrint('[LyxPanel] Permisos efectivos para grupo', group, ':', json.encode(effective))
            cb({
                access = true,
                group = group,
                permissions = effective,
                security = GetPanelActionSecurityForClient(source),
                integrations = {
                    lyxGuard = (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) or false
                }
            })
        else
            DebugPrint('[LyxPanel] Acceso denegado para:', source)
            cb({ access = false })
        end
    end)

    ESX.RegisterServerCallback('lyxpanel:getPlayers', function(source, cb)
        if not HasPanelAccess(source) then return cb({}) end

        local players = {}
        for _, xP in pairs(ESX.GetExtendedPlayers()) do
            local ped = GetPlayerPed(xP.source)
            local coords = GetEntityCoords(ped)
            players[#players + 1] = {
                id = xP.source,
                identifier = xP.identifier,
                name = GetPlayerName(xP.source),
                job = xP.getJob().label,
                jobName = xP.getJob().name,
                money = xP.getMoney(),
                bank = xP.getAccount('bank').money,
                group = xP.getGroup(),
                health = GetEntityHealth(ped),
                armor = GetPedArmour(ped),
                coords = { x = coords.x, y = coords.y, z = coords.z },
                ping = GetPlayerPing(xP.source)
            }
        end
        cb(players)
    end)

    ESX.RegisterServerCallback('lyxpanel:getPlayerDetails', function(source, cb, targetId)
        DebugPrint(('[LyxPanel] getPlayerDetails request from %d for target %s'):format(source, tostring(targetId)))

        local viewerAccess, viewerGroup = HasPanelAccess(source)
        if not viewerAccess then
            DebugPrint('[LyxPanel] getPlayerDetails DENIED: No panel access')
            return cb(nil)
        end

        -- Validate targetId
        targetId = tonumber(targetId)
        if not targetId or targetId <= 0 then
            DebugPrint(('[LyxPanel] getPlayerDetails FAILED: Invalid targetId: %s'):format(tostring(targetId)))
            return cb(nil)
        end

        local xP = ESX.GetPlayerFromId(targetId)
        if not xP then
            DebugPrint(('[LyxPanel] getPlayerDetails FAILED: ESX player not found for ID %d'):format(targetId))
            return cb(nil)
        end

        -- Ped is optional - some server configs can't get ped from server-side
        local ped = GetPlayerPed(targetId)
        local hasPed = ped and ped ~= 0

        if not hasPed then
            DebugPrint(('[LyxPanel] getPlayerDetails WARNING: No ped for ID %d, using ESX data only'):format(targetId))
        end

        -- Obtener coordenadas con manejo de error
        local coords = vector3(0, 0, 0)
        if hasPed then
            local success, result = pcall(function()
                return GetEntityCoords(ped)
            end)
            if success and result then coords = result end
        end

        -- Obtener datos del jugador con valores por defecto
        local jobData = xP.getJob() or { name = 'unemployed', label = 'Desempleado', grade = 0 }
        local bankAccount = xP.getAccount('bank') or { money = 0 }
        local blackAccount = xP.getAccount('black_money') or { money = 0 }

        -- Obtener salud y armadura con manejo de error
        local health = 200
        local maxHealth = 200
        local armor = 0

        if hasPed then
            pcall(function()
                health = GetEntityHealth(ped) or 200
                maxHealth = GetEntityMaxHealth(ped) or 200
                armor = GetPedArmour(ped) or 0
            end)
        end

        local playerData = {
            id = targetId,
            identifier = xP.identifier or 'unknown',
            name = GetPlayerName(targetId) or 'Unknown',
            job = {
                name = jobData.name or 'unemployed',
                label = jobData.label or 'Desempleado',
                grade = jobData.grade or 0
            },
            accounts = {
                money = xP.getMoney() or 0,
                bank = bankAccount.money or 0,
                black = blackAccount.money or 0
            },
            group = xP.getGroup() or 'user',
            health = health,
            maxHealth = maxHealth,
            armor = armor,
            coords = { x = coords.x or 0, y = coords.y or 0, z = coords.z or 0 },
            ping = GetPlayerPing(targetId) or 0,
            identifiers = {
                steam = GetIdentifier(targetId, 'steam'),
                discord = GetIdentifier(targetId, 'discord'),
                license = GetIdentifier(targetId, 'license')
            },
            inventory = xP.getInventory() or {},
            weapons = xP.getLoadout() or {},
            vehicle = nil,
            guard = { available = false }
        }

        -- Optional LyxGuard telemetry (best-effort, never hard fail the panel).
        local guardAvailable = (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) or false
        if guardAvailable then
            local hb = nil
            local risk = nil
            local ev = nil
            local q = nil

            pcall(function() hb = exports['lyx-guard']:GetHeartbeatState(targetId) end)
            pcall(function() risk = exports['lyx-guard']:GetRiskScore(targetId) end)
            pcall(function() ev = exports['lyx-guard']:GetPlayerEventStats(targetId) end)
            pcall(function() q = exports['lyx-guard']:GetQuarantineState(targetId) end)

            playerData.guard = {
                available = true,
                heartbeat = hb,
                risk = risk,
                eventStats = ev,
                quarantine = q,
                viewerGroup = viewerGroup
            }
        end

        local function _finish()
            DebugPrint(('[LyxPanel] getPlayerDetails SUCCESS for ID %d (%s)'):format(targetId, playerData.name))
            cb(playerData)
        end

        -- Optional LyxGuard history (requires canViewLogs; never blocks player details if DB fails).
        local pending = 1
        local function done()
            pending = pending - 1
            if pending <= 0 then
                _finish()
            end
        end

        if guardAvailable and playerData.guard and playerData.guard.available == true
            and HasPermission(source, 'canViewLogs')
            and playerData.identifier and playerData.identifier ~= 'unknown'
        then
            pending = pending + 1
            MySQL.query(
                'SELECT id, detection_type, punishment, detection_date FROM lyxguard_detections WHERE identifier = ? ORDER BY detection_date DESC LIMIT 10',
                { playerData.identifier },
                function(r)
                    playerData.guard.detections = r or {}
                    done()
                end
            )

            pending = pending + 1
            MySQL.query(
                'SELECT id, reason, warned_by, warn_date, expires_at, active FROM lyxguard_warnings WHERE identifier = ? ORDER BY warn_date DESC LIMIT 10',
                { playerData.identifier },
                function(r)
                    playerData.guard.warnings = r or {}
                    done()
                end
            )
        end

        done()
    end)


    ESX.RegisterServerCallback('lyxpanel:getStats', function(source, cb)
        if not HasPanelAccess(source) then return cb({}) end

        local stats = {
            playersOnline = #GetPlayers(),
            maxPlayers = GetConvarInt('sv_maxclients', 32),
            detectionsToday = 0,
            bansTotal = 0,
            reportsOpen = 0,
            guardAvailable = false
        }

        local guardAvailable = (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) or false
        stats.guardAvailable = guardAvailable

        -- Usar promesas para mejor rendimiento
        local pending = 1 + (guardAvailable and 2 or 0)
        local function done()
            pending = pending - 1
            if pending == 0 then cb(stats) end
        end

        if guardAvailable then
            MySQL.scalar('SELECT COUNT(*) FROM lyxguard_detections WHERE DATE(detection_date) = CURDATE()', {}, function(r)
                stats.detectionsToday = r or 0
                done()
            end)

            MySQL.scalar('SELECT COUNT(*) FROM lyxguard_bans WHERE active = 1', {}, function(r)
                stats.bansTotal = r or 0
                done()
            end)
        end

        MySQL.scalar("SELECT COUNT(*) FROM lyxpanel_reports WHERE status = 'open'", {}, function(r)
            stats.reportsOpen = r or 0
            done()
        end)
    end)

    ESX.RegisterServerCallback('lyxpanel:getDetections', function(source, cb, limit)
        if not HasPermission(source, 'canViewLogs') then return cb({}) end
        if not (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) then
            return cb({})
        end
        MySQL.query('SELECT * FROM lyxguard_detections ORDER BY detection_date DESC LIMIT ?', { limit or 100 },
            function(r)
                cb(r or {})
            end)
    end)

    ESX.RegisterServerCallback('lyxpanel:getBans', function(source, cb)
        if not HasPermission(source, 'canManageBans') then return cb({}) end
        if not (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) then
            return cb({})
        end
        MySQL.query('SELECT * FROM lyxguard_bans ORDER BY ban_date DESC', {}, function(r) cb(r or {}) end)
    end)

    ESX.RegisterServerCallback('lyxpanel:getReports', function(source, cb)
        if not HasPermission(source, 'canManageReports') then return cb({}) end
        MySQL.query('SELECT * FROM lyxpanel_reports ORDER BY created_at DESC', {}, function(r) cb(r or {}) end)
    end)

    ESX.RegisterServerCallback('lyxpanel:getLogs', function(source, cb, limit)
        if not HasPermission(source, 'canViewLogs') then return cb({}) end
        MySQL.query('SELECT * FROM lyxpanel_logs ORDER BY created_at DESC LIMIT ?', { limit or 100 },
            function(r) cb(r or {}) end)
    end)

    -- -----------------------------------------------------------------------
    -- AUDIT / LOG QUERIES (filters + pagination) + export
    -- -----------------------------------------------------------------------

    local function _ClampInt(v, minV, maxV, def)
        local n = tonumber(v)
        if not n then return def end
        n = math.floor(n)
        if n < minV then return minV end
        if n > maxV then return maxV end
        return n
    end

    local function _SanitizeLike(s, maxLen)
        if type(s) ~= 'string' then s = tostring(s or '') end
        s = s:gsub('[%c]', ''):gsub('[\r\n\t]', ' ')
        if maxLen and #s > maxLen then
            s = s:sub(1, maxLen)
        end
        s = s:match('^%s*(.-)%s*$') or s
        if s == '' then return nil end
        return '%' .. s .. '%'
    end

    local function _NormalizeDateBound(dateStr, isEnd)
        if type(dateStr) ~= 'string' then return nil end
        dateStr = dateStr:match('^%s*(.-)%s*$') or dateStr
        if dateStr:match('^%d%d%d%d%-%d%d%-%d%d$') then
            return dateStr .. (isEnd and ' 23:59:59' or ' 00:00:00')
        end
        if dateStr:match('^%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d:%d%d$') then
            return dateStr
        end
        return nil
    end

    local function _BuildLogsWhere(filters, outParams)
        local where = ' WHERE 1=1'
        outParams = outParams or {}

        -- Convenience flags
        if filters.onlyDenied == true then
            where = where .. ' AND action = ?'
            table.insert(outParams, 'DENIED_PERMISSION')
        end

        if filters.onlyDangerous == true then
            local dangerous = { 'WIPE_PLAYER', 'BAN', 'UNBAN', 'GIVE_MONEY', 'SET_MONEY', 'REMOVE_MONEY', 'GIVE_MONEY_ALL' }
            local ph = {}
            for _, a in ipairs(dangerous) do
                table.insert(ph, '?')
                table.insert(outParams, a)
            end
            where = where .. ' AND action IN (' .. table.concat(ph, ',') .. ')'
        end

        -- Actions filter (string or array)
        if type(filters.actions) == 'string' and filters.actions ~= '' then
            filters.actions = { filters.actions }
        end
        if type(filters.actions) == 'table' and #filters.actions > 0 then
            local ph = {}
            for _, a in ipairs(filters.actions) do
                if type(a) == 'string' then
                    a = a:match('^%s*(.-)%s*$') or a
                    if a:match('^[%w_%-%:]+$') and #a <= 64 then
                        table.insert(ph, '?')
                        table.insert(outParams, a)
                    end
                end
            end
            if #ph > 0 then
                where = where .. ' AND action IN (' .. table.concat(ph, ',') .. ')'
            end
        end

        local adminLike = _SanitizeLike(filters.admin, 64)
        if adminLike then
            where = where .. ' AND (admin_name LIKE ? OR admin_id LIKE ?)'
            table.insert(outParams, adminLike)
            table.insert(outParams, adminLike)
        end

        local targetLike = _SanitizeLike(filters.target, 64)
        if targetLike then
            where = where .. ' AND (target_name LIKE ? OR target_id LIKE ?)'
            table.insert(outParams, targetLike)
            table.insert(outParams, targetLike)
        end

        local dateFrom = _NormalizeDateBound(filters.dateFrom, false)
        if dateFrom then
            where = where .. ' AND created_at >= ?'
            table.insert(outParams, dateFrom)
        end

        local dateTo = _NormalizeDateBound(filters.dateTo, true)
        if dateTo then
            where = where .. ' AND created_at <= ?'
            table.insert(outParams, dateTo)
        end

        local correlationLike = _SanitizeLike(filters.correlationId, 128)
        if correlationLike then
            where = where .. " AND JSON_UNQUOTE(JSON_EXTRACT(details, '$.correlation_id')) LIKE ?"
            table.insert(outParams, correlationLike)
        end

        local level = _SanitizeLike(filters.level, 16)
        if level then
            where = where .. " AND JSON_UNQUOTE(JSON_EXTRACT(details, '$.level')) LIKE ?"
            table.insert(outParams, level)
        end

        local result = _SanitizeLike(filters.result, 32)
        if result then
            where = where .. " AND JSON_UNQUOTE(JSON_EXTRACT(details, '$.result')) LIKE ?"
            table.insert(outParams, result)
        end

        local q = _SanitizeLike(filters.search, 80)
        if q then
            where = where .. " AND (action LIKE ? OR admin_name LIKE ? OR target_name LIKE ? OR CAST(details AS CHAR) LIKE ?)"
            table.insert(outParams, q)
            table.insert(outParams, q)
            table.insert(outParams, q)
            table.insert(outParams, q)
        end

        return where, outParams
    end

    local function _CsvEscape(s)
        s = tostring(s or '')
        s = s:gsub('\"', '\"\"')
        if s:find('[,\r\n\"]') then
            return '\"' .. s .. '\"'
        end
        return s
    end

    ESX.RegisterServerCallback('lyxpanel:queryLogs', function(source, cb, filters)
        if not HasPermission(source, 'canViewLogs') then return cb({ success = false, error = 'no_permission' }) end

        filters = type(filters) == 'table' and filters or {}
        local limit = _ClampInt(filters.limit, 1, 200, 100)
        local offset = _ClampInt(filters.offset, 0, 5000, 0)

        local params = {}
        local where = _BuildLogsWhere(filters, params)

        local countSql = 'SELECT COUNT(*) AS total FROM lyxpanel_logs' .. where
        MySQL.query(countSql, params, function(countRows)
            local total = countRows and countRows[1] and tonumber(countRows[1].total) or 0

            local dataSql = 'SELECT * FROM lyxpanel_logs' .. where .. ' ORDER BY created_at DESC LIMIT ? OFFSET ?'
            local dataParams = {}
            for i = 1, #params do dataParams[i] = params[i] end
            table.insert(dataParams, limit)
            table.insert(dataParams, offset)

            MySQL.query(dataSql, dataParams, function(rows)
                cb({ success = true, total = total, rows = rows or {} })
            end)
        end)
    end)

    ESX.RegisterServerCallback('lyxpanel:exportLogs', function(source, cb, opts)
        if not HasPermission(source, 'canViewLogs') then return cb({ success = false, error = 'no_permission' }) end

        opts = type(opts) == 'table' and opts or {}
        local format = tostring(opts.format or 'json'):lower()
        if format ~= 'json' and format ~= 'csv' then format = 'json' end

        local filters = type(opts.filters) == 'table' and opts.filters or {}
        local maxExport = _ClampInt(opts.maxRows, 1, 2000, 500)

        local params = {}
        local where = _BuildLogsWhere(filters, params)
        local sql = 'SELECT * FROM lyxpanel_logs' .. where .. ' ORDER BY created_at DESC LIMIT ?'
        table.insert(params, maxExport)

        MySQL.query(sql, params, function(rows)
            rows = rows or {}

            if format == 'json' then
                cb({
                    success = true,
                    format = 'json',
                    filename = ('lyxpanel_logs_%s.json'):format(os.date('%Y%m%d_%H%M%S')),
                    content = json.encode(rows)
                })
                return
            end

            local out = {}
            table.insert(out, 'id,created_at,admin_id,admin_name,action,target_id,target_name,details')
            for _, r in ipairs(rows) do
                table.insert(out, table.concat({
                    _CsvEscape(r.id),
                    _CsvEscape(r.created_at),
                    _CsvEscape(r.admin_id),
                    _CsvEscape(r.admin_name),
                    _CsvEscape(r.action),
                    _CsvEscape(r.target_id),
                    _CsvEscape(r.target_name),
                    _CsvEscape(r.details)
                }, ','))
            end

            cb({
                success = true,
                format = 'csv',
                filename = ('lyxpanel_logs_%s.csv'):format(os.date('%Y%m%d_%H%M%S')),
                content = table.concat(out, '\n')
            })
        end)
    end)

    -- -----------------------------------------------------------------------
    -- PERMISSION MANAGEMENT (masters only)
    -- -----------------------------------------------------------------------

    local function _IsMaster(source)
        local ok, group = HasPanelAccess(source)
        if not ok then return false end
        return group == 'master' or group == 'owner' or group == 'superadmin'
    end

    local function _Trim(v)
        if type(v) ~= 'string' then
            v = tostring(v or '')
        end
        v = v:gsub('[%c]', ' ')
        return (v:match('^%s*(.-)%s*$') or '')
    end

    local function _SanitizeToken(v, minLen, maxLen, pattern)
        local s = _Trim(v)
        if maxLen and #s > maxLen then
            s = s:sub(1, maxLen)
        end
        if minLen and #s < minLen then
            return nil
        end
        if pattern and not s:match(pattern) then
            return nil
        end
        return s
    end

    local function _BuildRoleNameSet()
        local out = {}
        local rp = Config and Config.Permissions and Config.Permissions.rolePermissions or {}
        for role, _ in pairs(rp) do
            if type(role) == 'string' and role ~= '' then
                out[role] = true
            end
        end
        return out
    end

    local function _BuildPermissionKeySet()
        local out = {}
        local rp = Config and Config.Permissions and Config.Permissions.rolePermissions or {}
        for _, perms in pairs(rp) do
            if type(perms) == 'table' then
                for k, _ in pairs(perms) do
                    if type(k) == 'string' and k:match('^[%a][%w_]*$') then
                        out[k] = true
                    end
                end
            end
        end
        return out
    end

    local function _NormalizeBoolLike(value)
        if value == true then return true end
        if value == false then return false end

        if type(value) == 'number' then
            if value == 1 then return true end
            if value == 0 then return false end
            return nil
        end

        if type(value) == 'string' then
            local s = value:lower()
            if s == '1' or s == 'true' or s == 'yes' or s == 'on' then
                return true
            end
            if s == '0' or s == 'false' or s == 'no' or s == 'off' then
                return false
            end
        end

        return nil
    end

    local function _IsValidAccessIdentifier(value)
        if type(value) ~= 'string' then return false end
        value = value:gsub('%s+', '')
        local prefix, rest = value:match('^(%w+):([%w]+)$')
        if not prefix or not rest then return false end

        local allowed = {
            license = true,
            license2 = true,
            steam = true,
            discord = true,
            fivem = true,
            xbl = true,
            live = true
        }
        if not allowed[prefix] then return false end
        return true
    end

    local function _LogPermissionEditorReject(source, endpoint, reason, payload)
        local adminName = GetPlayerName(source) or 'unknown'
        local adminId = GetIdentifier(source, 'license') or 'unknown'
        if type(LogAction) == 'function' then
            pcall(function()
                LogAction(adminId, adminName, 'PERMISSION_EDITOR_REJECT', tostring(source), adminName, {
                    endpoint = tostring(endpoint or 'unknown'),
                    reason = tostring(reason or 'invalid_input'),
                    payload = payload or {}
                })
            end)
        end

        if Config and Config.Security and Config.Security.forwardDeniedToLyxGuard == true
            and exports['lyx-guard'] and exports['lyx-guard'].LogDetection
        then
            pcall(function()
                exports['lyx-guard']:LogDetection(source, 'lyxpanel_permission_editor_reject', {
                    endpoint = tostring(endpoint or 'unknown'),
                    reason = tostring(reason or 'invalid_input'),
                    payload = payload or {}
                }, nil, 'flagged')
            end)
        end
    end

    ESX.RegisterServerCallback('lyxpanel:getPermissionEditorData', function(source, cb)
        if not _IsMaster(source) then return cb({ success = false, error = 'no_permission' }) end

        local roles = {}
        local keys = {}
        local rp = Config and Config.Permissions and Config.Permissions.rolePermissions or {}
        for role, perms in pairs(rp) do
            table.insert(roles, role)
            if type(perms) == 'table' then
                for k, _ in pairs(perms) do
                    keys[k] = true
                end
            end
        end

        local permissionKeys = {}
        for k, _ in pairs(keys) do table.insert(permissionKeys, k) end
        table.sort(roles)
        table.sort(permissionKeys)

        cb({ success = true, roles = roles, permissionKeys = permissionKeys })
    end)

    ESX.RegisterServerCallback('lyxpanel:getRolePermissions', function(source, cb, role)
        if not _IsMaster(source) then return cb({ success = false, error = 'no_permission' }) end
        local roleName = _SanitizeToken(role, 1, 32, '^[%w_%-]+$')
        if not roleName then
            return cb({ success = false, error = 'invalid_role' })
        end

        local roleSet = _BuildRoleNameSet()
        if not roleSet[roleName] then
            return cb({ success = false, error = 'unknown_role' })
        end

        local base = (Config and Config.Permissions and Config.Permissions.rolePermissions and Config.Permissions.rolePermissions[roleName]) or {}

        local override = nil
        if LyxPanel and LyxPanel.PermissionsStore then
            override = LyxPanel.PermissionsStore.GetRoleOverride(roleName)
        end

        local effective = {}
        for k, v in pairs(base) do effective[k] = v end
        if override and type(override.perms) == 'table' then
            for k, v in pairs(override.perms) do effective[k] = v end
        end

        cb({ success = true, role = roleName, base = base, override = override and override.perms or nil, effective = effective })
    end)

    ESX.RegisterServerCallback('lyxpanel:setRolePermission', function(source, cb, role, perm, value)
        if not _IsMaster(source) then return cb({ success = false, error = 'no_permission' }) end
        if not (LyxPanel and LyxPanel.PermissionsStore) then return cb({ success = false, error = 'store_missing' }) end

        local roleName = _SanitizeToken(role, 1, 32, '^[%w_%-]+$')
        if not roleName then
            _LogPermissionEditorReject(source, 'setRolePermission', 'invalid_role', { role = role })
            return cb({ success = false, error = 'invalid_role' })
        end

        local roleSet = _BuildRoleNameSet()
        if not roleSet[roleName] then
            _LogPermissionEditorReject(source, 'setRolePermission', 'unknown_role', { role = roleName })
            return cb({ success = false, error = 'unknown_role' })
        end

        local permKey = _SanitizeToken(perm, 1, 64, '^[%a][%w_]*$')
        if not permKey then
            _LogPermissionEditorReject(source, 'setRolePermission', 'invalid_permission', { permission = perm })
            return cb({ success = false, error = 'invalid_permission' })
        end

        local permSet = _BuildPermissionKeySet()
        if not permSet[permKey] then
            _LogPermissionEditorReject(source, 'setRolePermission', 'unknown_permission', { permission = permKey })
            return cb({ success = false, error = 'unknown_permission' })
        end

        local v = _NormalizeBoolLike(value)
        if v == nil then
            _LogPermissionEditorReject(source, 'setRolePermission', 'invalid_value', { value = value })
            return cb({ success = false, error = 'invalid_value' })
        end

        local actorName = GetPlayerName(source) or 'unknown'
        local actorId = GetIdentifier(source, 'license') or 'unknown'

        local ok = LyxPanel.PermissionsStore.SetRolePermission(roleName, permKey, v, actorName, actorId)
        cb({ success = ok == true })
    end)

    ESX.RegisterServerCallback('lyxpanel:resetRoleOverride', function(source, cb, role)
        if not _IsMaster(source) then return cb({ success = false, error = 'no_permission' }) end
        if not (LyxPanel and LyxPanel.PermissionsStore) then return cb({ success = false, error = 'store_missing' }) end

        local roleName = _SanitizeToken(role, 1, 32, '^[%w_%-]+$')
        if not roleName then
            return cb({ success = false, error = 'invalid_role' })
        end

        local roleSet = _BuildRoleNameSet()
        if not roleSet[roleName] then
            return cb({ success = false, error = 'unknown_role' })
        end

        local actorName = GetPlayerName(source) or 'unknown'
        local actorId = GetIdentifier(source, 'license') or 'unknown'
        local ok = LyxPanel.PermissionsStore.ResetRole(roleName, actorName, actorId)
        cb({ success = ok == true })
    end)

    ESX.RegisterServerCallback('lyxpanel:getIndividualPermissions', function(source, cb, identifier)
        if not _IsMaster(source) then return cb({ success = false, error = 'no_permission' }) end
        if not (LyxPanel and LyxPanel.PermissionsStore) then return cb({ success = false, error = 'store_missing' }) end
        identifier = tostring(identifier or ''):gsub('%s+', '')
        if not _IsValidAccessIdentifier(identifier) then
            return cb({ success = false, error = 'invalid_identifier' })
        end
        cb({ success = true, identifier = identifier, overrides = LyxPanel.PermissionsStore.GetIndividualOverride(identifier) or {} })
    end)

    ESX.RegisterServerCallback('lyxpanel:setIndividualPermission', function(source, cb, identifier, perm, value)
        if not _IsMaster(source) then return cb({ success = false, error = 'no_permission' }) end
        if not (LyxPanel and LyxPanel.PermissionsStore) then return cb({ success = false, error = 'store_missing' }) end

        identifier = tostring(identifier or ''):gsub('%s+', '')
        if not _IsValidAccessIdentifier(identifier) then
            _LogPermissionEditorReject(source, 'setIndividualPermission', 'invalid_identifier', { identifier = identifier })
            return cb({ success = false, error = 'invalid_identifier' })
        end

        local permKey = _SanitizeToken(perm, 1, 64, '^[%a][%w_]*$')
        if not permKey then
            _LogPermissionEditorReject(source, 'setIndividualPermission', 'invalid_permission', { permission = perm })
            return cb({ success = false, error = 'invalid_permission' })
        end

        local permSet = _BuildPermissionKeySet()
        if not permSet[permKey] then
            _LogPermissionEditorReject(source, 'setIndividualPermission', 'unknown_permission', { permission = permKey })
            return cb({ success = false, error = 'unknown_permission' })
        end

        local v = _NormalizeBoolLike(value)
        if v == nil then
            _LogPermissionEditorReject(source, 'setIndividualPermission', 'invalid_value', { value = value })
            return cb({ success = false, error = 'invalid_value' })
        end

        local actorName = GetPlayerName(source) or 'unknown'
        local actorId = GetIdentifier(source, 'license') or 'unknown'

        local ok = LyxPanel.PermissionsStore.SetIndividualPermission(identifier, permKey, v, actorName, actorId)
        cb({ success = ok == true })
    end)

    ESX.RegisterServerCallback('lyxpanel:resetIndividualPermission', function(source, cb, identifier, perm)
        if not _IsMaster(source) then return cb({ success = false, error = 'no_permission' }) end
        if not (LyxPanel and LyxPanel.PermissionsStore) then return cb({ success = false, error = 'store_missing' }) end

        local cleanIdentifier = tostring(identifier or ''):gsub('%s+', '')
        if not _IsValidAccessIdentifier(cleanIdentifier) then
            return cb({ success = false, error = 'invalid_identifier' })
        end

        local permKey = _SanitizeToken(perm, 1, 64, '^[%a][%w_]*$')
        if not permKey then
            return cb({ success = false, error = 'invalid_permission' })
        end

        local permSet = _BuildPermissionKeySet()
        if not permSet[permKey] then
            return cb({ success = false, error = 'unknown_permission' })
        end

        local actorName = GetPlayerName(source) or 'unknown'
        local actorId = GetIdentifier(source, 'license') or 'unknown'
        local ok = LyxPanel.PermissionsStore.ResetIndividual(cleanIdentifier, permKey, actorName, actorId)
        cb({ success = ok == true })
    end)

    -- -----------------------------------------------------------------------
    -- PANEL ACCESS LIST (masters only)
    -- -----------------------------------------------------------------------

    ESX.RegisterServerCallback('lyxpanel:listAccessEntries', function(source, cb)
        if not _IsMaster(source) then return cb({ success = false, error = 'no_permission' }) end
        if not (LyxPanel and LyxPanel.AccessStore) then return cb({ success = false, error = 'store_missing' }) end
        cb({ success = true, rows = LyxPanel.AccessStore.List() })
    end)

    ESX.RegisterServerCallback('lyxpanel:setAccessEntry', function(source, cb, identifier, groupName, note)
        if not _IsMaster(source) then return cb({ success = false, error = 'no_permission' }) end
        if not (LyxPanel and LyxPanel.AccessStore) then return cb({ success = false, error = 'store_missing' }) end

        identifier = tostring(identifier or ''):gsub('%s+', '')
        groupName = _SanitizeToken(groupName, 1, 32, '^[%w_%-]+$')
        note = _Trim(note)
        if #note > 200 then
            note = note:sub(1, 200)
        end

        if not _IsValidAccessIdentifier(identifier) then
            _LogPermissionEditorReject(source, 'setAccessEntry', 'invalid_identifier', { identifier = identifier })
            return cb({ success = false, error = 'invalid_identifier' })
        end

        local roleSet = _BuildRoleNameSet()
        if not groupName or not roleSet[groupName] then
            _LogPermissionEditorReject(source, 'setAccessEntry', 'invalid_group', { group = groupName })
            return cb({ success = false, error = 'invalid_group' })
        end

        local actorName = GetPlayerName(source) or 'unknown'
        local actorId = GetIdentifier(source, 'license') or 'unknown'

        local ok, err = LyxPanel.AccessStore.Set(identifier, groupName, note, actorName, actorId)
        cb({ success = ok == true, error = err })
    end)

    ESX.RegisterServerCallback('lyxpanel:removeAccessEntry', function(source, cb, identifier)
        if not _IsMaster(source) then return cb({ success = false, error = 'no_permission' }) end
        if not (LyxPanel and LyxPanel.AccessStore) then return cb({ success = false, error = 'store_missing' }) end

        identifier = tostring(identifier or ''):gsub('%s+', '')
        if not _IsValidAccessIdentifier(identifier) then
            return cb({ success = false, error = 'invalid_identifier' })
        end

        local actorName = GetPlayerName(source) or 'unknown'
        local actorId = GetIdentifier(source, 'license') or 'unknown'

        local ok, err = LyxPanel.AccessStore.Remove(identifier, actorName, actorId)
        cb({ success = ok == true, error = err })
    end)

    ESX.RegisterServerCallback('lyxpanel:getTickets', function(source, cb)
        if not HasPermission(source, 'canUseTickets') then return cb({}) end
        MySQL.query('SELECT * FROM lyxpanel_tickets ORDER BY created_at DESC', {}, function(r) cb(r or {}) end)
    end)

    ESX.RegisterServerCallback('lyxpanel:getJobs', function(source, cb)
        if not HasPanelAccess(source) then return cb({}) end
        MySQL.query('SELECT * FROM jobs', {}, function(jobs)
            local result = {}
            for _, job in ipairs(jobs or {}) do
                local grades = MySQL.Sync.fetchAll('SELECT * FROM job_grades WHERE job_name = ? ORDER BY grade',
                    { job.name })
                result[job.name] = { name = job.name, label = job.label, grades = grades }
            end
            cb(result)
        end)
    end)

    ESX.RegisterServerCallback('lyxpanel:getConfig', function(source, cb)
        if not HasPanelAccess(source) then return cb({}) end
        local guardAvailable = (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) or false
        cb({
            weapons = Config.Weapons,
            vehicles = Config.Vehicles,
            customVehicles = GetCustomVehicles(),
            items = Config.CommonItems,
            weather = Config.Weather,
            spawnPoints = Config.SpawnPoints or {},
            themes = Config.Themes or {},
            runtimeProfile = tostring(Config.RuntimeProfile or 'default'),
            dependencies = {
                lyxGuardAvailable = guardAvailable
            }
        })
    end)

    ESX.RegisterServerCallback('lyxpanel:getDependencyStatus', function(source, cb)
        if not HasPanelAccess(source) then
            cb({ success = false, error = 'no_permission' })
            return
        end

        local out = {
            success = true,
            timestamp = os.time(),
            panel = {
                state = GetResourceState('lyx-panel'),
                runtimeProfile = tostring(Config.RuntimeProfile or 'default')
            },
            guard = {
                state = GetResourceState('lyx-guard'),
                available = false,
                serverReady = false,
                heartbeat = {
                    onlinePlayers = 0,
                    healthyHeartbeats = 0,
                    staleHeartbeats = 0,
                    maxAgeMs = 0
                },
                risk = {
                    players = 0,
                    avg = 0,
                    max = 0
                }
            }
        }

        local guardAvailable = (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) or false
        if guardAvailable and out.guard.state == 'started' then
            out.guard.available = true

            local ready = false
            pcall(function()
                ready = exports['lyx-guard']:IsServerReady() == true
            end)
            out.guard.serverReady = ready == true

            local staleThresholdMs = 45000
            local players = GetPlayers()
            out.guard.heartbeat.onlinePlayers = #players

            local riskSum = 0
            local riskPlayers = 0
            local riskMax = 0

            for _, pid in ipairs(players) do
                local src = tonumber(pid)
                if src and src > 0 then
                    local hb = nil
                    pcall(function()
                        hb = exports['lyx-guard']:GetHeartbeatState(src)
                    end)

                    local ageMs = hb and tonumber(hb.ageMs) or nil
                    if ageMs and ageMs >= 0 then
                        if ageMs > out.guard.heartbeat.maxAgeMs then
                            out.guard.heartbeat.maxAgeMs = ageMs
                        end
                        if ageMs <= staleThresholdMs then
                            out.guard.heartbeat.healthyHeartbeats = out.guard.heartbeat.healthyHeartbeats + 1
                        else
                            out.guard.heartbeat.staleHeartbeats = out.guard.heartbeat.staleHeartbeats + 1
                        end
                    else
                        out.guard.heartbeat.staleHeartbeats = out.guard.heartbeat.staleHeartbeats + 1
                    end

                    local r = nil
                    pcall(function()
                        r = exports['lyx-guard']:GetRiskScore(src)
                    end)
                    r = tonumber(r)
                    if r and r > 0 then
                        riskPlayers = riskPlayers + 1
                        riskSum = riskSum + r
                        if r > riskMax then
                            riskMax = r
                        end
                    end
                end
            end

            out.guard.risk.players = riskPlayers
            out.guard.risk.max = riskMax
            if riskPlayers > 0 then
                out.guard.risk.avg = math.floor((riskSum / riskPlayers) + 0.5)
            end
        end

        cb(out)
    end)


    print('^2[LyxPanel v4.0]^7 ESX Callbacks registered')
end)

-- 
-- COMANDO PRINCIPAL
-- 

RegisterCommand(Config.OpenCommand or 'panel', function(source)
    if source > 0 and HasPanelAccess(source) then
        TouchPanelSession(source)
        TriggerClientEvent('lyxpanel:open', source)
    end
end, false)

RegisterNetEvent('lyxpanel:panelSession', function(opened)
    local src = source
    if not src or src <= 0 then return end

    if type(opened) ~= 'boolean' then
        ActivePanelSessions[src] = nil
        _PanelActionSecurityState.sessions[src] = nil
        _PanelActionSecurityState.contexts[src] = nil
        _HandlePanelSessionSpoof(src)
        return
    end

    if opened == true then
        local access = HasPanelAccess(src)
        if access then
            TouchPanelSession(src)
            _IssuePanelActionSession(src, false)
        else
            ActivePanelSessions[src] = nil
            _PanelActionSecurityState.sessions[src] = nil
            _PanelActionSecurityState.contexts[src] = nil
            _HandlePanelSessionSpoof(src)
        end
    else
        ActivePanelSessions[src] = nil
        _PanelActionSecurityState.sessions[src] = nil
        _PanelActionSecurityState.contexts[src] = nil
    end
end)

-- 
-- STAFF STATUS SYSTEM
-- 

local ActiveStaff = {}
local StaffSubscribers = {}

local function SendStaffStatusToSubscribers()
    local staffList = {}
    for _, data in pairs(ActiveStaff) do
        table.insert(staffList, data)
    end

    for src, _ in pairs(StaffSubscribers) do
        if not GetPlayerName(src) then
            StaffSubscribers[src] = nil
        else
            local access = HasPanelAccess(src)
            if access then
                TriggerClientEvent('lyxpanel:syncStaffStatus', src, staffList)
            else
                StaffSubscribers[src] = nil
            end
        end
    end
end

RegisterNetEvent('lyxpanel:setStaffStatus', function(active, role)
    local src = source
    local access, group = HasPanelAccess(src)
    if not access then return end

    local playerName = GetPlayerName(src)

    if active then
        ActiveStaff[src] = {
            id = src,
            name = playerName,
            role = group or 'STAFF'
        }
    else
        ActiveStaff[src] = nil
    end

    SendStaffStatusToSubscribers()
end)

-- Cleanup on disconnect
AddEventHandler('playerDropped', function()
    if ActiveStaff[source] then
        ActiveStaff[source] = nil
        SendStaffStatusToSubscribers()
    end

    StaffSubscribers[source] = nil
    ActivePanelSessions[source] = nil
    _PanelSessionSpoofCooldowns[source] = nil
    _PanelActionSecurityState.sessions[source] = nil
    _PanelActionSecurityState.contexts[source] = nil
end)

-- Sync when player joins
RegisterNetEvent('lyxpanel:requestStaffSync', function()
    local src = source
    if src <= 0 then return end

    local access = HasPanelAccess(src)
    if not access then return end

    StaffSubscribers[src] = true

    local staffList = {}
    for _, data in pairs(ActiveStaff) do
        table.insert(staffList, data)
    end
    TriggerClientEvent('lyxpanel:syncStaffStatus', src, staffList)
end)

-- 
-- EXPORTS
-- 

exports('HasPanelAccess', HasPanelAccess)
exports('HasPermission', HasPermission)
exports('LogAction', LogAction)
exports('IsPanelSessionActive', IsPanelSessionActive)
exports('TouchPanelSession', TouchPanelSession)
exports('ValidatePanelActionEnvelope', ValidatePanelActionEnvelope)
exports('GetPanelActionSecurityForClient', GetPanelActionSecurityForClient)

print('^2[LyxPanel v4.0]^7 Server main loaded')




