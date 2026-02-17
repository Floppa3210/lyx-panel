--[[
    
                        LYXPANEL v4.0 - EXTENDED ACTIONS                          
                          Advanced Administration Features                         
    
      Features: Server Control, Advanced Bans, Jail, Mute, Whitelist, etc.        
    
]]

-- 
-- SERVER CONTROL - REMOVED FOR SECURITY
-- These features (restart server, kick all, manage resources) have been removed
-- as they pose security risks. Use txAdmin for server management instead.
-- 

-- 
-- ADVANCED BAN SYSTEM
-- 

-- ---------------------------------------------------------------------------
-- SECURITY: clamps + rate-limit + sanitization
-- ---------------------------------------------------------------------------

-- Prefer ESX global from @es_extended/imports.lua, but register callbacks only
-- once ESX is actually ready to avoid nil crashes on resource startup.
local ESX = ESX
local _PendingESXCallbacks = {}
local _CallbacksFlushed = false

local function _ResolveESX(timeoutMs)
    if ESX then return ESX end

    if LyxPanel and LyxPanel.WaitForESX then
        ESX = LyxPanel.WaitForESX(timeoutMs or 15000)
        if ESX then
            _G.ESX = _G.ESX or ESX
        end
        return ESX
    end

    return ESX
end

local function RegisterESXCallback(name, handler)
    if ESX and _CallbacksFlushed then
        ESX.RegisterServerCallback(name, handler)
        return
    end

    _PendingESXCallbacks[#_PendingESXCallbacks + 1] = {
        name = name,
        handler = handler
    }
end

CreateThread(function()
    local resolved = _ResolveESX(15000)
    if not resolved then
        print('^1[LyxPanel]^7 actions_extended: ESX no disponible (timeout), callbacks no registrados.')
        return
    end

    ESX = resolved
    _G.ESX = _G.ESX or ESX

    for i = 1, #_PendingESXCallbacks do
        local entry = _PendingESXCallbacks[i]
        ESX.RegisterServerCallback(entry.name, entry.handler)
    end

    _PendingESXCallbacks = {}
    _CallbacksFlushed = true
end)

local _ActionCooldowns = {}

local function _IsRateLimited(src, key, cooldownMs)
    if not src or src <= 0 then return true end

    local now = GetGameTimer()
    _ActionCooldowns[src] = _ActionCooldowns[src] or {}
    local last = _ActionCooldowns[src][key] or 0

    if (now - last) < (cooldownMs or 0) then
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

local function _RequireLyxGuard(src, featureLabel)
    if LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable() then
        return true
    end

    if LyxPanel and LyxPanel.WarnIfMissingDependency then
        LyxPanel.WarnIfMissingDependency('lyx-guard', featureLabel or 'feature')
    end
    if src and src > 0 then
        TriggerClientEvent('lyxpanel:notify', src, 'error', 'lyx-guard no esta activo (feature deshabilitada)')
    end
    return false
end

local function _AsInt(v, default)
    local n = tonumber(v)
    if not n then return default end
    return math.floor(n)
end

local function _ClampInt(v, min, max, default)
    local n = tonumber(v)
    if not n then return default end
    n = math.floor(n)
    if n < min then return min end
    if n > max then return max end
    return n
end

local function _SanitizeText(text, maxLen)
    if type(text) ~= 'string' then
        text = tostring(text or '')
    end

    text = text:gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')

    if maxLen and #text > maxLen then
        text = text:sub(1, maxLen)
    end

    return text
end

local function _AsPlayerId(id)
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    if not GetPlayerName(id) then return nil end
    return id
end

local function _IsValidIdentifier(identifier)
    if type(identifier) ~= 'string' then return false end
    identifier = identifier:gsub('%s+', '')
    if #identifier < 5 or #identifier > 128 then return false end

    local prefix, value = identifier:match('^(%w+):(.+)$')
    if not prefix or not value then return false end

    prefix = prefix:lower()
    local allowed = {
        license = true,
        steam = true,
        discord = true,
        fivem = true,
        xbl = true,
        live = true,
    }
    if not allowed[prefix] then return false end

    if value:match('^[%w]+$') == nil then return false end
    return true
end

local function _NormalizeIpRange(ipRange)
    if type(ipRange) ~= 'string' then return nil end
    ipRange = ipRange:gsub('%s+', '')

    local a, b, c = ipRange:match('^(%d+)%.(%d+)%.(%d+)%.%*$')
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if not a or not b or not c then return nil end
    if a < 0 or a > 255 or b < 0 or b > 255 or c < 0 or c > 255 then return nil end

    return string.format('%d.%d.%d.*', a, b, c)
end

local function _NormalizePlate(plate)
    plate = tostring(plate or ''):upper():gsub('%s+', '')
    plate = plate:gsub('[^A-Z0-9]', '')
    local maxLen = _GetLimitNumber('maxPlateLength', 8)
    if #plate > maxLen then
        plate = plate:sub(1, maxLen)
    end
    if plate == '' then return nil end
    return plate
end

local function _NormalizeModelName(model)
    model = tostring(model or ''):gsub('%s+', '')
    local maxLen = _GetLimitNumber('maxVehicleModelLength', 32)
    if #model < 1 or #model > maxLen then return nil end
    if model:match('^[%w_]+$') == nil then return nil end
    return model
end

-- Offline ban (by identifier)
RegisterNetEvent('lyxpanel:action:banOffline', function(identifier, reason, duration, playerName)
    local s = source
    if not HasPermission(s, 'canBanOffline') then return end
    if _IsRateLimited(s, 'banOffline', _GetCooldownMs('banOffline', 1500)) then return end
    if not _RequireLyxGuard(s, 'banOffline') then return end

    identifier = tostring(identifier or ''):gsub('%s+', '')
    if not _IsValidIdentifier(identifier) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Identifier invalido')
        return
    end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    local nameMax = _GetLimitNumber('maxPlayerNameLength', 100)
    reason = _SanitizeText(reason or 'Ban offline', reasonMax)
    if reason == '' then reason = 'Ban offline' end
    playerName = _SanitizeText(playerName or 'Unknown', nameMax)
    if playerName == '' then playerName = 'Unknown' end

    local isPermanent = false
    local hours = nil
    if type(duration) == 'string' and duration:lower() == 'permanent' then
        isPermanent = true
    else
        local d = tonumber(duration)
        if d and d == 0 then
            isPermanent = true
        else
            local maxHours = _GetLimitNumber('maxOfflineBanHours', 24 * 365)
            hours = _ClampInt(duration, 1, maxHours, 24)
        end
    end
    local unbanTime = nil

    if not isPermanent and hours then
        unbanTime = os.date('%Y-%m-%d %H:%M:%S', os.time() + (hours * 3600))
    end

    MySQL.Async.execute([[
        INSERT INTO lyxguard_bans (identifier, player_name, reason, unban_date, permanent, banned_by)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { identifier, playerName, reason, unbanTime, isPermanent and 1 or 0, GetPlayerName(s) })

    TriggerEvent('lyxguard:reloadBans')
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'BAN_OFFLINE', identifier, playerName,
        { reason = reason, duration = duration, hours = hours, permanent = isPermanent })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Ban offline aplicado a ' .. playerName)
end)

-- IP Range ban
RegisterNetEvent('lyxpanel:action:banIPRange', function(ipRange, reason)
    local s = source
    if not HasPermission(s, 'canBanIP') then return end
    if _IsRateLimited(s, 'banIPRange', _GetCooldownMs('banIPRange', 1500)) then return end

    -- Format: 192.168.1.*
    ipRange = _NormalizeIpRange(ipRange)
    if not ipRange then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Formato IP invalido (ej: 192.168.1.*)')
        return
    end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    reason = _SanitizeText(reason or 'IP Range Ban', reasonMax)
    if reason == '' then reason = 'IP Range Ban' end

    MySQL.Async.execute([[
        INSERT INTO lyxpanel_ip_bans (ip_range, reason, banned_by, created_at)
        VALUES (?, ?, ?, NOW())
    ]], { ipRange, reason, GetPlayerName(s) })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'BAN_IP_RANGE', nil, nil, { ipRange = ipRange, reason = reason })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Rango IP baneado: ' .. ipRange)
end)

-- Reduce ban time
RegisterNetEvent('lyxpanel:action:reduceBan', function(banId, hours)
    local s = source
    if not HasPermission(s, 'canManageBans') then return end
    if _IsRateLimited(s, 'reduceBan', _GetCooldownMs('reduceBan', 1500)) then return end
    if not _RequireLyxGuard(s, 'reduceBan') then return end

    banId = _AsInt(banId, 0)
    if banId <= 0 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'BanID invalido')
        return
    end

    local maxHours = _GetLimitNumber('maxReduceBanHours', 24 * 365)
    hours = _ClampInt(hours, 1, maxHours, 24)

    MySQL.Async.execute([[
        UPDATE lyxguard_bans
        SET unban_date = DATE_SUB(unban_date, INTERVAL ? HOUR)
        WHERE id = ? AND permanent = 0 AND active = 1
    ]], { hours, banId })

    TriggerEvent('lyxguard:reloadBans')
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'REDUCE_BAN', nil, 'BanID:' .. banId, { hours = hours })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Ban reducido ' .. hours .. ' horas')
end)

-- 
-- ENHANCED WARNING SYSTEM
-- 

RegisterNetEvent('lyxpanel:action:warnWithEscalation', function(targetId, reason)
    local s = source
    if not HasPermission(s, 'canWarn') then return end
    if _IsRateLimited(s, 'warnWithEscalation', _GetCooldownMs('warnWithEscalation', 1000)) then return end
    if not _RequireLyxGuard(s, 'warnWithEscalation') then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    reason = _SanitizeText(reason or 'Advertencia', reasonMax)
    if reason == '' then reason = 'Advertencia' end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end

    local identifier = xT.identifier

    -- Insert warning
    MySQL.Async.execute([[
        INSERT INTO lyxguard_warnings (identifier, player_name, reason, warned_by, expires_at)
        VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 7 DAY))
    ]], { identifier, GetPlayerName(targetId), reason, GetPlayerName(s) })

    -- Count active warnings
    MySQL.Async.fetchScalar([[
        SELECT COUNT(*) FROM lyxguard_warnings
        WHERE identifier = ? AND active = 1 AND (expires_at IS NULL OR expires_at > NOW())
    ]], { identifier }, function(count)
        count = count or 0

        -- Escalation thresholds
        local maxWarnings = Config and Config.Punishments and Config.Punishments.warnings and
            Config.Punishments.warnings.maxWarnings or 3

        if count >= maxWarnings then
            -- Auto-ban (requires lyx-guard)
            if LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable() and exports['lyx-guard'] then
                exports['lyx-guard']:BanPlayer(targetId, 'Maximo de advertencias alcanzado', 'medium', 'Sistema')
                TriggerClientEvent('lyxpanel:notify', s, 'warning', 'Jugador auto-baneado (max warnings)')
            else
                TriggerClientEvent('lyxpanel:notify', s, 'warning', 'Mx warnings alcanzado (lyx-guard no activo)')
            end
        else
            TriggerClientEvent('lyxpanel:notify', targetId, 'warning',
                string.format('ADVERTENCIA %d/%d: %s', count, maxWarnings, reason))
            TriggerClientEvent('lyxpanel:notify', s, 'success',
                string.format('Warning %d/%d aplicado', count, maxWarnings))
        end
    end)

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'WARN_ESCALATION', identifier, GetPlayerName(targetId),
        { reason = reason })
end)

-- Clear all warnings
RegisterNetEvent('lyxpanel:action:clearWarnings', function(targetId)
    local s = source
    if not HasPermission(s, 'canClearWarnings') then return end
    if _IsRateLimited(s, 'clearWarnings', _GetCooldownMs('clearWarnings', 1000)) then return end
    if not _RequireLyxGuard(s, 'clearWarnings') then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end

    MySQL.Async.execute('UPDATE lyxguard_warnings SET active = 0 WHERE identifier = ?', { xT.identifier })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_WARNINGS', xT.identifier, GetPlayerName(targetId), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Warnings limpiados')
end)

-- 
-- JAIL/PRISON SYSTEM
-- 

local JailedPlayers = {}

local function _GuardSafeMovement(playerId)
    if not (LyxPanel and LyxPanel.TryGuardSafe) then return end
    local ms = 5000
    if LyxPanel.GetGuardSafeMs then
        ms = LyxPanel.GetGuardSafeMs('movement', ms) or ms
    end
    -- lyx-guard uses 'teleport' as the safe key for teleport-related detections.
    LyxPanel.TryGuardSafe(playerId, { 'movement', 'teleport' }, ms)
end

RegisterNetEvent('lyxpanel:action:jail', function(targetId, time, reason)
    local s = source
    if not HasPermission(s, 'canJail') then return end
    if _IsRateLimited(s, 'jail', _GetCooldownMs('jail', 1000)) then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    local maxMinutes = _GetLimitNumber('maxJailMinutes', 240)
    time = _ClampInt(time, 1, maxMinutes, 5) -- Minutes

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    reason = _SanitizeText(reason or 'Mala conducta', reasonMax)
    if reason == '' then reason = 'Mala conducta' end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end

    JailedPlayers[targetId] = {
        releaseTime = os.time() + (time * 60),
        reason = reason,
        jailedBy = GetPlayerName(s)
    }

    -- Teleport to jail
    local jailCoords = { x = 1679.13, y = 2515.90, z = 45.56 } -- Default jail coords
    _GuardSafeMovement(targetId)
    TriggerClientEvent('lyxpanel:teleport', targetId, jailCoords.x, jailCoords.y, jailCoords.z)
    TriggerClientEvent('lyxpanel:setJailed', targetId, true, time, reason)

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'JAIL', xT.identifier, GetPlayerName(targetId),
        { time = time, reason = reason })
    TriggerClientEvent('lyxpanel:notify', s, 'success', GetPlayerName(targetId) .. ' encarcelado por ' .. time .. ' min')
    TriggerClientEvent('lyxpanel:notify', targetId, 'warning', 'Encarcelado por ' .. time .. ' min: ' .. reason)
end)

RegisterNetEvent('lyxpanel:action:unjail', function(targetId)
    local s = source
    if not HasPermission(s, 'canJail') then return end
    if _IsRateLimited(s, 'unjail', _GetCooldownMs('unjail', 1000)) then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    if JailedPlayers[targetId] then
        JailedPlayers[targetId] = nil
        TriggerClientEvent('lyxpanel:setJailed', targetId, false)

        -- Teleport out
        local exitCoords = { x = 428.15, y = -981.45, z = 30.71 }
        _GuardSafeMovement(targetId)
        TriggerClientEvent('lyxpanel:teleport', targetId, exitCoords.x, exitCoords.y, exitCoords.z)

        LogAction(GetId(s, 'license'), GetPlayerName(s), 'UNJAIL', nil, GetPlayerName(targetId), {})
        TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador liberado')
        TriggerClientEvent('lyxpanel:notify', targetId, 'success', 'Has sido liberado')
    else
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador no esta en prision')
    end
end)

-- Periodic jail check
CreateThread(function()
    while true do
        Wait(30000) -- Check every 30s
        local now = os.time()
        for playerId, data in pairs(JailedPlayers) do
            if data.releaseTime <= now then
                JailedPlayers[playerId] = nil
                if GetPlayerName(playerId) then
                    TriggerClientEvent('lyxpanel:setJailed', playerId, false)
                    local exitCoords = { x = 428.15, y = -981.45, z = 30.71 }
                    _GuardSafeMovement(playerId)
                    TriggerClientEvent('lyxpanel:teleport', playerId, exitCoords.x, exitCoords.y, exitCoords.z)
                    TriggerClientEvent('lyxpanel:notify', playerId, 'success', 'Tu condena ha terminado')
                end
            end
        end
    end
end)

-- 
-- MUTE SYSTEM
-- 

local MutedPlayers = {}

RegisterNetEvent('lyxpanel:action:muteChat', function(targetId, time)
    local s = source
    if not HasPermission(s, 'canMute') then return end
    if _IsRateLimited(s, 'muteChat', _GetCooldownMs('muteChat', 1000)) then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    local maxMinutes = _GetLimitNumber('maxMuteMinutes', 240)
    time = _ClampInt(time, 1, maxMinutes, 10) -- Minutes

    MutedPlayers[targetId] = {
        type = 'chat',
        releaseTime = os.time() + (time * 60),
        mutedBy = GetPlayerName(s)
    }

    TriggerClientEvent('lyxpanel:setMuted', targetId, true, 'chat', time)

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'MUTE_CHAT', nil, GetPlayerName(targetId), { time = time })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador muteado ' .. time .. ' min')
    TriggerClientEvent('lyxpanel:notify', targetId, 'warning', 'Chat muteado por ' .. time .. ' min')
end)

RegisterNetEvent('lyxpanel:action:muteVoice', function(targetId, time)
    local s = source
    if not HasPermission(s, 'canMute') then return end
    if _IsRateLimited(s, 'muteVoice', _GetCooldownMs('muteVoice', 1000)) then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    local maxMinutes = _GetLimitNumber('maxMuteMinutes', 240)
    time = _ClampInt(time, 1, maxMinutes, 10)

    MutedPlayers[targetId] = {
        type = 'voice',
        releaseTime = os.time() + (time * 60),
        mutedBy = GetPlayerName(s)
    }

    TriggerClientEvent('lyxpanel:setMuted', targetId, true, 'voice', time)

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'MUTE_VOICE', nil, GetPlayerName(targetId), { time = time })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Voz muteada ' .. time .. ' min')
end)

RegisterNetEvent('lyxpanel:action:unmute', function(targetId)
    local s = source
    if not HasPermission(s, 'canMute') then return end
    if _IsRateLimited(s, 'unmute', _GetCooldownMs('unmute', 1000)) then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    MutedPlayers[targetId] = nil
    TriggerClientEvent('lyxpanel:setMuted', targetId, false)

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'UNMUTE', nil, GetPlayerName(targetId), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador desmuteado')
    TriggerClientEvent('lyxpanel:notify', targetId, 'success', 'Has sido desmuteado')
end)

-- Export mute check for chat resources
exports('IsPlayerMuted', function(playerId)
    local data = MutedPlayers[playerId]
    if data then
        if data.releaseTime > os.time() then
            return true, data.type
        else
            MutedPlayers[playerId] = nil
        end
    end
    return false, nil
end)

-- 
-- PLAYER HISTORY & SEARCH
-- 

RegisterESXCallback('lyxpanel:searchPlayer', function(source, cb, searchTerm)
    if not HasPanelAccess(source) then
        cb({})
        return
    end

    if not (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) then
        cb({})
        return
    end

    local maxLen = _GetLimitNumber('maxSearchTermLength', 50)
    searchTerm = _SanitizeText(searchTerm or '', maxLen)
    if searchTerm == '' then
        cb({})
        return
    end
    searchTerm = '%' .. searchTerm .. '%'

    MySQL.Async.fetchAll([[
        SELECT DISTINCT identifier, player_name, MAX(detection_date) as last_seen
        FROM lyxguard_detections
        WHERE identifier LIKE ? OR player_name LIKE ?
        GROUP BY identifier
        ORDER BY last_seen DESC
        LIMIT 50
    ]], { searchTerm, searchTerm }, function(results)
        cb(results or {})
    end)
end)

RegisterESXCallback('lyxpanel:getPlayerHistory', function(source, cb, identifier)
    if not HasPermission(source, 'canViewHistory') then
        cb({})
        return
    end

    if not (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) then
        cb({})
        return
    end

    identifier = tostring(identifier or ''):gsub('%s+', '')
    if not _IsValidIdentifier(identifier) then
        cb({})
        return
    end

    local history = {
        bans = {},
        warnings = {},
        detections = {},
        transactions = {}
    }

    local pending = 4
    local function checkDone()
        pending = pending - 1
        if pending == 0 then cb(history) end
    end

    MySQL.Async.fetchAll('SELECT * FROM lyxguard_bans WHERE identifier = ? ORDER BY ban_date DESC LIMIT 20',
        { identifier },
        function(r)
            history.bans = r or {}
            checkDone()
        end)

    MySQL.Async.fetchAll('SELECT * FROM lyxguard_warnings WHERE identifier = ? ORDER BY warn_date DESC LIMIT 20',
        { identifier },
        function(r)
            history.warnings = r or {}
            checkDone()
        end)

    MySQL.Async.fetchAll('SELECT * FROM lyxguard_detections WHERE identifier = ? ORDER BY detection_date DESC LIMIT 50',
        { identifier },
        function(r)
            history.detections = r or {}
            checkDone()
        end)

    MySQL.Async.fetchAll('SELECT * FROM lyxpanel_transactions WHERE player_id = ? ORDER BY created_at DESC LIMIT 50',
        { identifier },
        function(r)
            history.transactions = r or {}
            checkDone()
        end)
end)

-- 
-- WHITELIST MANAGEMENT
-- 

-- 
-- SCHEDULED ANNOUNCEMENTS
-- 

local ScheduledAnnouncements = {}
local NextAnnouncementId = 0

RegisterNetEvent('lyxpanel:action:scheduleAnnounce', function(message, delayMinutes, repeatEvery)
    local s = source
    if not HasPermission(s, 'canAnnounce') then return end
    if _IsRateLimited(s, 'scheduleAnnounce', _GetCooldownMs('scheduleAnnounce', 1500)) then return end

    local maxCount = _GetLimitNumber('maxScheduleAnnouncements', 50)
    local currentCount = 0
    for _ in pairs(ScheduledAnnouncements) do
        currentCount = currentCount + 1
    end
    if currentCount >= maxCount then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Lmite de anuncios programados alcanzado')
        return
    end

    local msgMax = _GetLimitNumber('maxAnnouncementLength', 250)
    message = _SanitizeText(message, msgMax)
    if not message or message == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Mensaje invalido')
        return
    end

    local maxDelay = _GetLimitNumber('maxScheduleDelayMinutes', 1440)
    delayMinutes = _ClampInt(delayMinutes, 1, maxDelay, 1)

    local repeatMinutes = tonumber(repeatEvery)
    local maxRepeat = _GetLimitNumber('maxScheduleRepeatMinutes', 1440)
    if repeatMinutes then
        repeatMinutes = math.floor(repeatMinutes)
        if repeatMinutes < 1 then
            repeatMinutes = nil
        elseif repeatMinutes > maxRepeat then
            repeatMinutes = maxRepeat
        end
    end

    NextAnnouncementId = NextAnnouncementId + 1
    local id = NextAnnouncementId
    ScheduledAnnouncements[id] = {
        message = message,
        nextTrigger = os.time() + (delayMinutes * 60),
        repeatEvery = repeatMinutes and (repeatMinutes * 60) or nil,
        createdBy = GetPlayerName(s)
    }

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SCHEDULE_ANNOUNCE', nil, nil,
        { message = message, delay = delayMinutes, repeatEvery = repeatMinutes })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Anuncio programado en ' .. delayMinutes .. ' min')
end)

-- Scheduled announcement checker
CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for id, ann in pairs(ScheduledAnnouncements) do
            if ann.nextTrigger <= now then
                TriggerClientEvent('lyxpanel:announce', -1, ann.message, 'info')
                if ann.repeatEvery then
                    ann.nextTrigger = now + ann.repeatEvery
                else
                    ScheduledAnnouncements[id] = nil
                end
            end
        end
    end
end)

-- 
-- SERVER STATISTICS
-- 

RegisterESXCallback('lyxpanel:getServerStats', function(source, cb)
    if not HasPanelAccess(source) then
        cb({})
        return
    end

    local stats = {
        players = #GetPlayers(),
        maxPlayers = GetConvarInt('sv_maxclients', 32),
        uptime = math.floor(GetGameTimer() / 1000),
        resources = {},
        guardAvailable = (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) or false
    }

    -- Get resource count
    local resCount = GetNumResources()
    local running = 0
    for i = 0, resCount - 1 do
        local res = GetResourceByFindIndex(i)
        if GetResourceState(res) == 'started' then
            running = running + 1
        end
    end
    stats.resourcesRunning = running
    stats.resourcesTotal = resCount

    -- Database stats
    local pending = 2 + (stats.guardAvailable and 3 or 0)
    local function checkDone()
        pending = pending - 1
        if pending == 0 then cb(stats) end
    end

    if stats.guardAvailable then
        MySQL.Async.fetchScalar('SELECT COUNT(*) FROM lyxguard_bans WHERE active = 1', {}, function(r)
            stats.activeBans = r or 0
            checkDone()
        end)

        MySQL.Async.fetchScalar('SELECT COUNT(*) FROM lyxguard_detections WHERE DATE(detection_date) = CURDATE()', {}, function(r)
            stats.detectionsToday = r or 0
            checkDone()
        end)

        MySQL.Async.fetchScalar('SELECT COUNT(*) FROM lyxguard_detections', {}, function(r)
            stats.detectionsTotal = r or 0
            checkDone()
        end)
    else
        stats.activeBans = 0
        stats.detectionsToday = 0
        stats.detectionsTotal = 0
    end

    MySQL.Async.fetchScalar('SELECT COUNT(*) FROM lyxpanel_logs WHERE DATE(created_at) = CURDATE()', {},
        function(r)
            stats.actionsToday = r or 0
            checkDone()
        end)

    MySQL.Async.fetchScalar("SELECT COUNT(*) FROM lyxpanel_reports WHERE status = 'open'", {},
        function(r)
            stats.openReports = r or 0
            checkDone()
        end)
end)

RegisterESXCallback('lyxpanel:getResourceList', function(source, cb)
    if not HasPermission(source, 'canManageResources') then
        cb({})
        return
    end

    local resources = {}
    local count = GetNumResources()

    for i = 0, count - 1 do
        local name = GetResourceByFindIndex(i)
        if name then
            table.insert(resources, {
                name = name,
                state = GetResourceState(name)
            })
        end
    end

    table.sort(resources, function(a, b) return a.name < b.name end)
    cb(resources)
end)

-- 
-- VEHICLE GARAGE MANAGEMENT
-- 

RegisterESXCallback('lyxpanel:getPlayerGarage', function(source, cb, targetId)
    if not HasPermission(source, 'canViewGarage') then
        cb({})
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then
        cb({})
        return
    end

    MySQL.Async.fetchAll([[
        SELECT plate, vehicle, stored, garage_name
        FROM owned_vehicles
        WHERE owner = ?
        ORDER BY vehicle
    ]], { xT.identifier }, function(vehicles)
        cb(vehicles or {})
    end)
end)

RegisterNetEvent('lyxpanel:action:giveVehicle', function(targetId, vehicleModel, plate)
    local s = source
    if not HasPermission(s, 'canGiveVehicle') then return end
    if _IsRateLimited(s, 'giveVehicle', _GetCooldownMs('giveVehicle', 1500)) then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    vehicleModel = _NormalizeModelName(vehicleModel)
    if not vehicleModel then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Modelo invalido')
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end

    plate = _NormalizePlate(plate) or ('ADMIN' .. math.random(100, 999))

    local vehicleData = {
        model = GetHashKey(vehicleModel),
        plate = plate
    }

    MySQL.Async.execute([[
        INSERT INTO owned_vehicles (owner, plate, vehicle)
        VALUES (?, ?, ?)
    ]], { xT.identifier, plate, json.encode(vehicleData) })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_VEHICLE', xT.identifier, GetPlayerName(targetId),
        { vehicle = vehicleModel, plate = plate })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Vehiculo anadido a garaje')
    TriggerClientEvent('lyxpanel:notify', targetId, 'info', 'Nuevo vehiculo en tu garaje: ' .. vehicleModel)
end)

RegisterNetEvent('lyxpanel:action:deleteGarageVehicle', function(targetId, plate)
    local s = source
    if not HasPermission(s, 'canDeleteVehicle') then return end
    if _IsRateLimited(s, 'deleteGarageVehicle', _GetCooldownMs('deleteGarageVehicle', 1500)) then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    plate = _NormalizePlate(plate)
    if not plate then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Patente invalida')
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end

    MySQL.Async.execute('DELETE FROM owned_vehicles WHERE owner = ? AND plate = ?', { xT.identifier, plate })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'DELETE_GARAGE_VEHICLE', xT.identifier, GetPlayerName(targetId),
        { plate = plate })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Vehiculo eliminado del garaje')
end)

-- 
-- LICENSES MANAGEMENT
-- 

RegisterESXCallback('lyxpanel:getPlayerLicenses', function(source, cb, targetId)
    if not HasPermission(source, 'canViewLicenses') then
        cb({})
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then
        cb({})
        return
    end

    MySQL.Async.fetchAll('SELECT * FROM user_licenses WHERE owner = ?', { xT.identifier }, function(licenses)
        cb(licenses or {})
    end)
end)

RegisterNetEvent('lyxpanel:action:giveLicense', function(targetId, licenseType)
    local s = source
    if not HasPermission(s, 'canGiveLicense') then return end
    if _IsRateLimited(s, 'giveLicense', _GetCooldownMs('giveLicense', 1500)) then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    licenseType = tostring(licenseType or ''):gsub('%s+', '')
    local maxLen = _GetLimitNumber('maxLicenseTypeLength', 64)
    if #licenseType < 1 or #licenseType > maxLen or licenseType:match('^[%w_]+$') == nil then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Tipo de licencia invalido')
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end

    MySQL.Async.execute([[
        INSERT IGNORE INTO user_licenses (type, owner)
        VALUES (?, ?)
    ]], { licenseType, xT.identifier })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_LICENSE', xT.identifier, GetPlayerName(targetId),
        { license = licenseType })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Licencia otorgada: ' .. licenseType)
    TriggerClientEvent('lyxpanel:notify', targetId, 'info', 'Has recibido licencia: ' .. licenseType)
end)

RegisterNetEvent('lyxpanel:action:removeLicense', function(targetId, licenseType)
    local s = source
    if not HasPermission(s, 'canRemoveLicense') then return end
    if _IsRateLimited(s, 'removeLicense', _GetCooldownMs('removeLicense', 1500)) then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    licenseType = tostring(licenseType or ''):gsub('%s+', '')
    local maxLen = _GetLimitNumber('maxLicenseTypeLength', 64)
    if #licenseType < 1 or #licenseType > maxLen or licenseType:match('^[%w_]+$') == nil then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Tipo de licencia invalido')
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end

    MySQL.Async.execute('DELETE FROM user_licenses WHERE owner = ? AND type = ?', { xT.identifier, licenseType })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'REMOVE_LICENSE', xT.identifier, GetPlayerName(targetId),
        { license = licenseType })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Licencia revocada')
end)

-- 
-- COPY PLAYER DATA
-- 

RegisterNetEvent('lyxpanel:action:copyPosition', function(targetId)
    local s = source
    if not HasPermission(s, 'canTeleport') then return end
    if _IsRateLimited(s, 'copyPosition', _GetCooldownMs('copyPosition', 500)) then return end

    targetId = _AsPlayerId(targetId)
    if not targetId then return end

    local ped = GetPlayerPed(targetId)
    if ped and ped ~= 0 then
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        local posStr = string.format('vector4(%.2f, %.2f, %.2f, %.2f)', coords.x, coords.y, coords.z, heading)
        TriggerClientEvent('lyxpanel:copyToClipboard', s, posStr)
        TriggerClientEvent('lyxpanel:notify', s, 'success', 'Posicion copiada')
    end
end)

print('^5[LyxPanel v4.0]^7 Extended actions loaded - 30+ new features')



