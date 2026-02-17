--[[
    
                        LYXPANEL v4.0 - SERVER ACTIONS                            
                        Optimizado para ESX Legacy 1.9+                            
    
]]

local ESX = ESX

CreateThread(function()
    local resolved = ESX
    if LyxPanel and LyxPanel.WaitForESX then
        resolved = LyxPanel.WaitForESX(15000)
    end

    if not resolved then
        print('^1[LyxPanel]^7 actions: ESX no disponible (timeout).')
        return
    end

    ESX = resolved
    _G.ESX = _G.ESX or resolved
end)

-- Utility function to get player identifier
local function GetId(source, idType)
    idType = idType or 'license'
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, idType .. ':') then
            return id
        end
    end
    return 'unknown'
end

local SpectateSessions = {}

local _ActionCooldowns = {}

local function _IsRateLimited(src, key, cooldownMs)
    if not src or src <= 0 then return true end

    local now = GetGameTimer()
    _ActionCooldowns[src] = _ActionCooldowns[src] or {}
    local last = _ActionCooldowns[src][key] or 0

    if (now - last) < cooldownMs then
        return true
    end

    _ActionCooldowns[src][key] = now
    return false
end

local function DebugPrint(...)
    if Config and Config.Debug then
        print(...)
    end
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

local function _GetGuardSafeMs(key, fallback)
    local limits = Config and Config.ActionLimits or nil
    local v = limits and limits.guardSafeMs and limits.guardSafeMs[key]
    if type(v) == 'number' then
        return v
    end
    return fallback
end

local function _AsInt(v, default)
    local n = tonumber(v)
    if not n then return default end
    n = math.floor(n)
    return n
end

local function _ClampInt(v, minV, maxV, default)
    local n = tonumber(v)
    if not n then return default end
    n = math.floor(n)
    if minV ~= nil and n < minV then n = minV end
    if maxV ~= nil and n > maxV then n = maxV end
    return n
end

local function _NormalizeRgbColor(value)
    if type(value) ~= 'table' then
        return nil
    end

    local r = _ClampInt(value.r, 0, 255, nil)
    local g = _ClampInt(value.g, 0, 255, nil)
    local b = _ClampInt(value.b, 0, 255, nil)
    if r == nil or g == nil or b == nil then
        return nil
    end

    return { r = r, g = g, b = b }
end

local function _AsBool(v, default)
    if type(v) == 'boolean' then return v end
    if type(v) == 'number' then return v ~= 0 end
    if type(v) == 'string' then
        local s = v:lower():gsub('%s+', '')
        if s == 'true' or s == '1' or s == 'yes' or s == 'y' or s == 'on' then return true end
        if s == 'false' or s == '0' or s == 'no' or s == 'n' or s == 'off' then return false end
    end
    return default
end

local function _NormalizeVehicleModel(model)
    if type(model) ~= 'string' then return nil end
    local maxLen = _GetLimitNumber('maxVehicleModelLength', 32)
    model = model:match('^%s*(.-)%s*$') or model
    model = model:gsub('%s+', ''):lower()
    if model == '' then return nil end
    if #model > maxLen then
        model = model:sub(1, maxLen)
    end
    if not model:match('^[%w_]+$') then
        return nil
    end
    return model
end

local function _NormalizePlateText(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:upper():gsub('%s+', '')
    plate = plate:gsub('[^A-Z0-9]', '')
    if plate == '' then return nil end
    if #plate > 8 then
        plate = plate:sub(1, 8)
    end
    return plate
end

local function _IsValidAccount(account)
    return account == 'money' or account == 'bank' or account == 'black_money'
end

local function _IsValidItemName(item)
    if type(item) ~= 'string' then return false end
    -- ESX item names are usually lowercase with underscores.
    return item:match('^[%w_]+$') ~= nil
end

local function _NormalizeWeaponName(weapon)
    weapon = tostring(weapon or ''):upper():gsub('%s+', '')
    if weapon == '' then return nil end
    if not weapon:match('^WEAPON_') then
        weapon = 'WEAPON_' .. weapon
    end
    if not weapon:match('^WEAPON_[A-Z0-9_]+$') then
        return nil
    end
    return weapon
end

local function _IsValidPanelIdentifier(identifier)
    if type(identifier) ~= 'string' then return false end
    identifier = identifier:gsub('%s+', '')
    if #identifier < 8 or #identifier > 128 then return false end

    local prefix, value = identifier:match('^(%w+):(.+)$')
    if not prefix or not value then return false end

    prefix = prefix:lower()
    local allowed = {
        license = true,
        steam = true,
        discord = true,
        fivem = true,
        xbl = true,
        live = true
    }
    if not allowed[prefix] then return false end

    return value:match('^[%w]+$') ~= nil
end

local function _AsTargetPlayer(s, targetId)
    local tid = tonumber(targetId)
    if not tid or tid == -1 then return s end
    if tid <= 0 then return nil end
    if not GetPlayerName(tid) then return nil end
    return tid
end

local function _TryGuardSafe(targetId, types, durationMs)
    if not targetId or targetId <= 0 then return false end
    if not (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) then
        return false
    end
    local ok = pcall(function()
        exports['lyx-guard']:SetPlayerSafe(targetId, types, durationMs)
    end)
    return ok == true
end

local function StopSpectateSession(src)
    local session = SpectateSessions[src]
    if not session then return end

    if GetPlayerName(src) and session.originalBucket ~= nil then
        SetPlayerRoutingBucket(src, session.originalBucket)
    end

    SpectateSessions[src] = nil
end

RegisterNetEvent('lyxpanel:spectate:end', function()
    local src = source
    StopSpectateSession(src)
end)

AddEventHandler('playerDropped', function()
    local src = source

    if SpectateSessions[src] then
        SpectateSessions[src] = nil
        return
    end

    if _ActionCooldowns[src] then
        _ActionCooldowns[src] = nil
    end

    for staffSrc, session in pairs(SpectateSessions) do
        if session and session.targetId == src then
            TriggerClientEvent('lyxpanel:spectate:stop', staffSrc)
            StopSpectateSession(staffSrc)
        end
    end
end)

-- 
-- ACCIONES BSICAS
-- 

RegisterNetEvent('lyxpanel:action:kick', function(targetId, reason)
    local s = source
    if not HasPermission(s, 'canKick') then return end
    if _IsRateLimited(s, 'kick', _GetCooldownMs('kick', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador invalido')
        return
    end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    reason = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(reason or '', reasonMax)) or tostring(reason or '')
    reason = reason:match('^%s*(.-)%s*$') or reason
    if reason == '' then reason = 'Sin razon' end

    local name = GetPlayerName(targetId) or 'Unknown'
    DropPlayer(targetId, 'LyxPanel | Expulsado: ' .. reason)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'KICK', GetId(targetId, 'license'), name, { reason = reason })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador expulsado')
end)

RegisterNetEvent('lyxpanel:action:ban', function(targetId, reason, duration, dryRun)
    local s = source
    if not HasPermission(s, 'canBan') then return end
    if _IsRateLimited(s, 'ban', _GetCooldownMs('ban', 1500)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador invalido')
        return
    end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    reason = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(reason or '', reasonMax)) or tostring(reason or '')
    reason = reason:match('^%s*(.-)%s*$') or reason
    if reason == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Motivo obligatorio')
        return
    end

    -- Parse duration:
    -- - "custom:hours" (UI)
    -- - number seconds
    -- - "permanent"/0 for permanent
    local durationSeconds = 0
    if type(duration) == 'string' then
        local d = duration:lower()
        if d:sub(1, 7) == 'custom:' then
            local hours = tonumber(d:sub(8)) or 1
            local maxHours = _GetLimitNumber('maxOfflineBanHours', 24 * 365)
            hours = math.max(1, math.min(hours, maxHours))
            durationSeconds = hours * 3600
        elseif d == 'permanent' or d == '0' then
            durationSeconds = 0
        else
            local n = tonumber(d)
            if n and n > 0 then durationSeconds = math.floor(n) end
        end
    elseif type(duration) == 'number' then
        if duration > 0 then durationSeconds = math.floor(duration) end
    end

    local maxSeconds = _GetLimitNumber('maxOfflineBanHours', 24 * 365) * 3600
    if durationSeconds > maxSeconds then durationSeconds = maxSeconds end

    local name = GetPlayerName(targetId)

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'BAN', GetId(targetId, 'license'), name,
            { reason = reason, duration = durationSeconds, rawDuration = duration, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] Ban simulado (no ejecutado)')
        return
    end

    if not (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) then
        if LyxPanel and LyxPanel.WarnIfMissingDependency then
            LyxPanel.WarnIfMissingDependency('lyx-guard', 'ban')
        end
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'LyxGuard no esta activo: bans deshabilitados')
        return
    end

    exports['lyx-guard']:BanPlayer(targetId, reason, durationSeconds == 0 and 0 or durationSeconds, GetPlayerName(s))
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'BAN', GetId(targetId, 'license'), name,
        { reason = reason, duration = durationSeconds, rawDuration = duration })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador baneado')
end)

RegisterNetEvent('lyxpanel:action:warn', function(targetId, reason)
    local s = source
    if not HasPermission(s, 'canWarn') then return end
    if _IsRateLimited(s, 'warn', _GetCooldownMs('warn', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador invalido')
        return
    end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    reason = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(reason or '', reasonMax)) or tostring(reason or '')
    reason = reason:match('^%s*(.-)%s*$') or reason
    if reason == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Motivo obligatorio')
        return
    end

    TriggerClientEvent('lyxpanel:notify', targetId, 'warning', 'Advertencia: ' .. reason)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'WARN', GetId(targetId, 'license'), GetPlayerName(targetId) or 'Unknown',
        { reason = reason })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Advertencia enviada')
end)

RegisterNetEvent('lyxpanel:action:unban', function(identifier, reason, dryRun)
    local s = source
    if not HasPermission(s, 'canManageBans') then return end
    if _IsRateLimited(s, 'unban', _GetCooldownMs('unban', 1500)) then return end

    identifier = tostring(identifier or ''):gsub('%s+', '')
    if identifier == '' or #identifier > 255 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Identifier invalido')
        return
    end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    reason = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(reason or '', reasonMax)) or tostring(reason or '')
    reason = reason:match('^%s*(.-)%s*$') or reason
    if reason == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Motivo obligatorio')
        return
    end

    if not (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) then
        if LyxPanel and LyxPanel.WarnIfMissingDependency then
            LyxPanel.WarnIfMissingDependency('lyx-guard', 'unban')
        end
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'LyxGuard no esta activo: unban deshabilitado')
        return
    end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'UNBAN', identifier, 'Offline',
            { reason = reason, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] Unban simulado (no ejecutado)')
        return
    end

    MySQL.update(
        'UPDATE lyxguard_bans SET active = 0, unbanned_by = ?, unban_reason = ? WHERE (identifier = ? OR license = ? OR steam = ?) AND active = 1',
        { GetPlayerName(s), reason, identifier, identifier, identifier },
        function(affected)
            local ok = affected and affected > 0
            if ok then
                TriggerEvent('lyxguard:reloadBans')
                TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador desbaneado')
            else
                TriggerClientEvent('lyxpanel:notify', s, 'error', 'No se pudo desbanear (no encontrado)')
            end

            LogAction(GetId(s, 'license'), GetPlayerName(s), 'UNBAN', identifier, 'Offline',
                { reason = reason, affected = affected or 0 })
        end
    )
end)

-- 
-- ECONOMA
-- 

RegisterNetEvent('lyxpanel:action:giveMoney', function(targetId, account, amount, dryRun)
    local s = source
    if not HasPermission(s, 'canGiveMoney') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'giveMoney', _GetCooldownMs('giveMoney', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    account = tostring(account or '')
    if not _IsValidAccount(account) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Cuenta invalida')
        return
    end

    amount = _AsInt(amount, 0)
    local moneyMax = _GetLimitNumber('moneyMax', 10000000)
    if amount <= 0 or amount > moneyMax then
        TriggerClientEvent('lyxpanel:notify', s, 'error', ('Monto invalido (1-%d)'):format(moneyMax))
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_MONEY', xT.identifier, GetPlayerName(targetId),
            { account = account, amount = amount, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] GiveMoney simulado (no ejecutado)')
        return
    end

    if account == 'money' then
        xT.addMoney(amount)
    elseif account == 'bank' then
        xT.addAccountMoney('bank', amount)
    elseif account == 'black_money' then
        xT.addAccountMoney('black_money', amount)
    end

    MySQL.insert(
        'INSERT INTO lyxpanel_transactions (player_id, player_name, type, amount, account, admin_id, admin_name) VALUES (?,?,?,?,?,?,?)',
        { xT.identifier, GetPlayerName(targetId), 'give', amount, account, GetId(s, 'license'), GetPlayerName(s) })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_MONEY', xT.identifier, GetPlayerName(targetId),
        { account = account, amount = amount })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Dinero entregado: $' .. amount)
    TriggerClientEvent('lyxpanel:notify', targetId, 'info', 'Recibiste $' .. amount)
end)

RegisterNetEvent('lyxpanel:action:setMoney', function(targetId, account, amount, dryRun)
    local s = source
    if not HasPermission(s, 'canSetMoney') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'setMoney', _GetCooldownMs('setMoney', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    account = tostring(account or '')
    if not _IsValidAccount(account) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Cuenta invalida')
        return
    end

    amount = _AsInt(amount, 0)
    local moneyMax = _GetLimitNumber('moneyMax', 10000000)
    if amount < 0 or amount > moneyMax then
        TriggerClientEvent('lyxpanel:notify', s, 'error', ('Monto invalido (0-%d)'):format(moneyMax))
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'SET_MONEY', xT.identifier, GetPlayerName(targetId),
            { account = account, amount = amount, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] SetMoney simulado (no ejecutado)')
        return
    end

    if account == 'money' then
        xT.setMoney(amount)
    elseif account == 'bank' then
        xT.setAccountMoney('bank', amount)
    elseif account == 'black_money' then
        xT.setAccountMoney('black_money', amount)
    end

    MySQL.insert(
        'INSERT INTO lyxpanel_transactions (player_id, player_name, type, amount, account, admin_id, admin_name) VALUES (?,?,?,?,?,?,?)',
        { xT.identifier, GetPlayerName(targetId), 'set', amount, account, GetId(s, 'license'), GetPlayerName(s) })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SET_MONEY', xT.identifier, GetPlayerName(targetId),
        { account = account, amount = amount })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Dinero establecido')
end)

RegisterNetEvent('lyxpanel:action:removeMoney', function(targetId, account, amount, dryRun)
    local s = source
    if not HasPermission(s, 'canSetMoney') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'removeMoney', _GetCooldownMs('removeMoney', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    account = tostring(account or '')
    if not _IsValidAccount(account) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Cuenta invalida')
        return
    end

    amount = _AsInt(amount, 0)
    local moneyMax = _GetLimitNumber('moneyMax', 10000000)
    if amount <= 0 or amount > moneyMax then
        TriggerClientEvent('lyxpanel:notify', s, 'error', ('Monto invalido (1-%d)'):format(moneyMax))
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'REMOVE_MONEY', xT.identifier, GetPlayerName(targetId),
            { account = account, amount = amount, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] RemoveMoney simulado (no ejecutado)')
        return
    end

    if account == 'money' then
        xT.removeMoney(amount)
    elseif account == 'bank' then
        xT.removeAccountMoney('bank', amount)
    elseif account == 'black_money' then
        xT.removeAccountMoney('black_money', amount)
    end

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'REMOVE_MONEY', xT.identifier, GetPlayerName(targetId),
        { account = account, amount = amount })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Dinero removido')
end)

RegisterNetEvent('lyxpanel:action:transferMoney', function(fromId, toId, account, amount, dryRun)
    local s = source
    if not HasPermission(s, 'canTransferMoney') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'transferMoney', _GetCooldownMs('transferMoney', 750)) then return end

    fromId = tonumber(fromId)
    toId = tonumber(toId)
    if not fromId or not toId or fromId <= 0 or toId <= 0 then return end
    if not GetPlayerName(fromId) or not GetPlayerName(toId) then return end

    account = tostring(account or '')
    if account ~= 'money' and account ~= 'bank' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Cuenta invalida')
        return
    end

    amount = _AsInt(amount, 0)
    local moneyMax = _GetLimitNumber('moneyMax', 10000000)
    if amount <= 0 or amount > moneyMax then
        TriggerClientEvent('lyxpanel:notify', s, 'error', ('Monto invalido (1-%d)'):format(moneyMax))
        return
    end

    local xFrom = ESX.GetPlayerFromId(fromId)
    local xTo = ESX.GetPlayerFromId(toId)
    if not xFrom or not xTo then return end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'TRANSFER_MONEY', nil, nil,
            { from = GetPlayerName(fromId), to = GetPlayerName(toId), amount = amount, account = account, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] TransferMoney simulado (no ejecutado)')
        return
    end

    if account == 'money' then
        xFrom.removeMoney(amount)
        xTo.addMoney(amount)
    elseif account == 'bank' then
        xFrom.removeAccountMoney('bank', amount)
        xTo.addAccountMoney('bank', amount)
    end

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TRANSFER_MONEY', nil, nil,
        { from = GetPlayerName(fromId), to = GetPlayerName(toId), amount = amount })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Transferencia completada')
end)

-- 
-- ARMAS E ITEMS
-- 

RegisterNetEvent('lyxpanel:action:giveWeapon', function(targetId, weapon, ammo)
    local s = source
    if not HasPermission(s, 'canGiveWeapons') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'giveWeapon', _GetCooldownMs('giveWeapon', 750)) then return end

    -- Handle -1 as "give to self"
    local actualTarget = tonumber(targetId)
    if not actualTarget or actualTarget == -1 then actualTarget = s end
    if actualTarget <= 0 or not GetPlayerName(actualTarget) then return end

    DebugPrint('[LyxPanel] GiveWeapon request from:', s, 'to:', actualTarget, 'Weapon:', weapon)

    local xT = ESX.GetPlayerFromId(actualTarget)
    if not xT then
        DebugPrint('[LyxPanel] GiveWeapon ERROR: Target not found via ESX')
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador no encontrado')
        return
    end

    -- Normalizar nombre del arma - asegurar formato WEAPON_xxx
    weapon = _NormalizeWeaponName(weapon)
    if not weapon then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Arma invalida')
        return
    end

    DebugPrint('[LyxPanel] GiveWeapon Normalized:', weapon)

    local ammoCount = _AsInt(ammo, 250)
    local ammoMax = _GetLimitNumber('weaponAmmoMax', 1000)
    if ammoCount < 0 or ammoCount > ammoMax then
        TriggerClientEvent('lyxpanel:notify', s, 'error',
            ('Municion invalida (0-%d)'):format(ammoMax))
        return
    end

    -- Usar ESX para registrar el arma en el inventario/base de datos
    -- Usar ESX para registrar el arma en el inventario/base de datos
    xT.addWeapon(weapon, ammoCount)

    -- Soporte para ox_inventory si est presente
    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:AddItem(actualTarget, weapon, 1, { ammo = ammoCount })
    end

    -- Trigger client direct give just in case (native) - but safeguard against dupes is tricky.
    -- Better rely on server-side inventory.

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_WEAPON', xT.identifier, GetPlayerName(actualTarget),
        { weapon = weapon, ammo = ammoCount })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Arma entregada: ' .. weapon)
    if actualTarget ~= s then
        TriggerClientEvent('lyxpanel:notify', actualTarget, 'info', 'Recibiste: ' .. weapon)
    end
end)

-- Dar solo municion (para armas que ya tiene el jugador)
RegisterNetEvent('lyxpanel:action:giveAmmo', function(targetId, weapon, ammo)
    local s = source
    if not HasPermission(s, 'canGiveWeapons') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'giveAmmo', _GetCooldownMs('giveAmmo', 750)) then return end

    local actualTarget = tonumber(targetId)
    if not actualTarget or actualTarget == -1 then actualTarget = s end
    if actualTarget <= 0 or not GetPlayerName(actualTarget) then return end

    local xT = ESX.GetPlayerFromId(actualTarget)
    if not xT then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador no encontrado')
        return
    end

    -- Normalizar nombre del arma
    weapon = _NormalizeWeaponName(weapon)
    if not weapon then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Arma invalida')
        return
    end

    local ammoCount = _AsInt(ammo, 250)
    local ammoMax = _GetLimitNumber('weaponAmmoMax', 1000)
    if ammoCount < 0 or ammoCount > ammoMax then
        TriggerClientEvent('lyxpanel:notify', s, 'error',
            ('Municion invalida (0-%d)'):format(ammoMax))
        return
    end

    -- Usar ESX para anadir municion
    if xT.addWeaponAmmo then
        xT.addWeaponAmmo(weapon, ammoCount)
    end

    -- Tambin triggerear en cliente para asegurar que se anade
    TriggerClientEvent('lyxpanel:giveAmmo', actualTarget, weapon, ammoCount)

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_AMMO', xT.identifier, GetPlayerName(actualTarget),
        { weapon = weapon, ammo = ammoCount })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Municion anadida: ' .. ammoCount .. ' balas')
    if actualTarget ~= s then
        TriggerClientEvent('lyxpanel:notify', actualTarget, 'info', 'Recibiste municion para ' .. weapon)
    end
end)


RegisterNetEvent('lyxpanel:action:heal', function(targetId)
    local s = source
    if not HasPermission(s, 'canHeal') then return end
    if _IsRateLimited(s, 'heal', _GetCooldownMs('heal', 750)) then return end

    local actualTarget = _AsTargetPlayer(s, targetId)
    if not actualTarget then return end

    if ESX then
        local xTarget = ESX.GetPlayerFromId(actualTarget)
        if xTarget then
            xTarget.triggerEvent('esx_basicneeds:healPlayer')
            xTarget.triggerEvent('esx_status:HealState')
        end
    end
    -- Also trigger basic native heal
    TriggerClientEvent('esx_ambulancejob:heal', actualTarget, 'big')
    _TryGuardSafe(actualTarget, { 'health' }, _GetGuardSafeMs('health', 3000))
    TriggerClientEvent('lyxpanel:heal', actualTarget)

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'HEAL', nil, GetPlayerName(actualTarget), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Curado')
end)

RegisterNetEvent('lyxpanel:action:removeWeapon', function(targetId, weapon)
    local s = source
    if not HasPermission(s, 'canRemoveWeapons') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'removeWeapon', _GetCooldownMs('removeWeapon', 750)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target then return end

    weapon = _NormalizeWeaponName(weapon)
    if not weapon then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Arma invalida')
        return
    end

    local xT = ESX.GetPlayerFromId(target)
    if xT and xT.removeWeapon then
        xT.removeWeapon(weapon)
    end

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'REMOVE_WEAPON', xT and xT.identifier or GetId(target, 'license'), GetPlayerName(target),
        { weapon = weapon })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Arma removida')
end)

RegisterNetEvent('lyxpanel:action:removeAllWeapons', function(targetId)
    local s = source
    if not HasPermission(s, 'canRemoveWeapons') then return end
    if _IsRateLimited(s, 'removeAllWeapons', _GetCooldownMs('removeAllWeapons', 1500)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target then return end

    local xT = ESX and ESX.GetPlayerFromId(target) or nil
    if xT and xT.removeAllWeapons then
        xT.removeAllWeapons()
    end

    TriggerClientEvent('lyxpanel:removeAllWeapons', target)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'REMOVE_ALL_WEAPONS', xT and xT.identifier or GetId(target, 'license'), GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Armas removidas')
    if target ~= s then
        TriggerClientEvent('lyxpanel:notify', target, 'warning', 'Tus armas fueron removidas por un admin')
    end
end)

RegisterNetEvent('lyxpanel:action:giveItem', function(targetId, item, count)
    local s = source
    if not HasPermission(s, 'canGiveItems') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'giveItem', _GetCooldownMs('giveItem', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    item = tostring(item or '')
    if not _IsValidItemName(item) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Item invalido')
        return
    end

    local c = _AsInt(count, 1)
    local itemMax = _GetLimitNumber('itemMaxCount', 100)
    if c <= 0 or c > itemMax then
        TriggerClientEvent('lyxpanel:notify', s, 'error',
            ('Cantidad invalida (1-%d)'):format(itemMax))
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if xT then xT.addInventoryItem(item, c) end
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_ITEM', xT and xT.identifier, GetPlayerName(targetId),
        { item = item, count = c })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Item entregado')
end)

RegisterNetEvent('lyxpanel:action:removeItem', function(targetId, item, count)
    local s = source
    if not HasPermission(s, 'canRemoveItems') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'removeItem', _GetCooldownMs('removeItem', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    item = tostring(item or '')
    if not _IsValidItemName(item) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Item invalido')
        return
    end

    local c = _AsInt(count, 1)
    local itemMax = _GetLimitNumber('itemMaxCount', 100)
    if c <= 0 or c > itemMax then
        TriggerClientEvent('lyxpanel:notify', s, 'error',
            ('Cantidad invalida (1-%d)'):format(itemMax))
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if xT then xT.removeInventoryItem(item, c) end
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Item removido')
end)

RegisterNetEvent('lyxpanel:action:clearInventory', function(targetId, dryRun)
    local s = source
    if not HasPermission(s, 'canClearInventory') then return end

    if _IsRateLimited(s, 'clearInventory', _GetCooldownMs('clearInventory', 1500)) then return end

    ESX = ESX or (_G.ESX)
    if not ESX and LyxPanel and LyxPanel.GetESX then
        ESX = LyxPanel.GetESX()
    end
    if not ESX then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'ESX no disponible')
        return
    end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    local xPlayer = ESX.GetPlayerFromId(targetId)
    if not xPlayer then return end

    local identifier = xPlayer.identifier or GetId(targetId, 'license') or 'unknown'
    local targetName = GetPlayerName(targetId) or 'Unknown'

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_INVENTORY', identifier, targetName, { dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] Clear inventory simulado (no ejecutado)')
        return
    end

    local inventory = xPlayer.getInventory and xPlayer.getInventory() or {}
    for _, item in pairs(inventory) do
        if item and item.name and tonumber(item.count) and item.count > 0 then
            xPlayer.removeInventoryItem(item.name, item.count)
        end
    end

    if xPlayer.removeAllWeapons then
        xPlayer.removeAllWeapons()
    end

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_INVENTORY', identifier, targetName, {})
    TriggerClientEvent('lyxpanel:notify', targetId, 'warning', 'Tu inventario ha sido limpiado por un admin')
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Inventario limpiado')
end)

-- 
-- VEHCULOS
-- 

RegisterNetEvent('lyxpanel:action:spawnVehicle', function(targetId, model)
    local s = source
    if not HasPermission(s, 'canSpawnVehicles') then return end
    if _IsRateLimited(s, 'spawnVehicle', _GetCooldownMs('spawnVehicle', 1000)) then return end
    local target = _AsTargetPlayer(s, targetId)
    if not target then return end
    model = _NormalizeVehicleModel(model)
    if not model then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Modelo de vehiculo invalido')
        return
    end

    -- Prevent LyxGuard entity firewall false-positives for legitimate admin spawns.
    _TryGuardSafe(target, { 'entity' }, _GetGuardSafeMs('entity', 6000))
    TriggerClientEvent('lyxpanel:spawnVehicle', target, model)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SPAWN_VEHICLE', GetId(target, 'license'), GetPlayerName(target),
        { model = model })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Vehiculo: ' .. model)
end)

RegisterNetEvent('lyxpanel:action:deleteVehicle', function(targetId)
    local s = source
    if not HasPermission(s, 'canDeleteVehicle') then return end
    if _IsRateLimited(s, 'deleteVehicle', _GetCooldownMs('deleteVehicle', 750)) then return end
    local target = _AsTargetPlayer(s, targetId)
    if not target then return end
    TriggerClientEvent('lyxpanel:deleteVehicle', target)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'DELETE_VEHICLE', GetId(target, 'license'), GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Vehiculo eliminado')
end)

RegisterNetEvent('lyxpanel:action:repairVehicle', function(targetId)
    local s = source
    if not HasPermission(s, 'canRepairVehicle') then return end
    if _IsRateLimited(s, 'repairVehicle', _GetCooldownMs('repairVehicle', 750)) then return end
    local target = _AsTargetPlayer(s, targetId)
    if not target then return end
    TriggerClientEvent('lyxpanel:repairVehicle', target)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'REPAIR_VEHICLE', GetId(target, 'license'), GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Vehiculo reparado')
end)

RegisterNetEvent('lyxpanel:action:flipVehicle', function(targetId)
    local s = source
    if not HasPermission(s, 'canFlipVehicle') then return end
    if _IsRateLimited(s, 'flipVehicle', _GetCooldownMs('flipVehicle', 750)) then return end
    local target = _AsTargetPlayer(s, targetId)
    if not target then return end
    TriggerClientEvent('lyxpanel:flipVehicle', target)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'FLIP_VEHICLE', GetId(target, 'license'), GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Vehiculo volteado')
end)

RegisterNetEvent('lyxpanel:action:boostVehicle', function(targetId)
    local s = source
    if not HasPermission(s, 'canBoostVehicle') then return end
    if _IsRateLimited(s, 'boostVehicle', _GetCooldownMs('boostVehicle', 1000)) then return end
    local target = _AsTargetPlayer(s, targetId)
    if not target then return end
    TriggerClientEvent('lyxpanel:boostVehicle', target)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'BOOST_VEHICLE', GetId(target, 'license'), GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Boost aplicado')
end)

RegisterNetEvent('lyxpanel:action:deleteNearbyVehicles', function()
    local s = source
    if not HasPermission(s, 'canDeleteNearby') then return end
    if _IsRateLimited(s, 'deleteNearbyVehicles', _GetCooldownMs('deleteNearbyVehicles', 5000)) then return end
    TriggerClientEvent('lyxpanel:deleteNearbyVehicles', s)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'DELETE_NEARBY_VEHICLES', GetId(s, 'license'), GetPlayerName(s), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Vehiculos cercanos eliminados')
end)

-- 
-- VEHCULOS AVANZADOS (v4.1)
-- 

-- Limpiar vehiculo (quitar suciedad y dao visual)
RegisterNetEvent('lyxpanel:action:cleanVehicle', function(targetId)
    local s = source
    if not HasPermission(s, 'canRepairVehicle') then return end
    if _IsRateLimited(s, 'cleanVehicle', _GetCooldownMs('cleanVehicle', 1000)) then return end
    local target = _AsTargetPlayer(s, targetId)
    if not target then return end
    TriggerClientEvent('lyxpanel:cleanVehicle', target)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAN_VEHICLE', GetId(target, 'license'), GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Vehiculo limpiado')
end)

-- Cambiar color del vehiculo
RegisterNetEvent('lyxpanel:action:setVehicleColor', function(targetId, primary, secondary)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end
    if _IsRateLimited(s, 'setVehicleColor', _GetCooldownMs('setVehicleColor', 1000)) then return end
    local target = _AsTargetPlayer(s, targetId)
    if not target then return end

    -- UI may send either GTA color indexes or RGB tables (from color picker).
    local primaryRgb = _NormalizeRgbColor(primary)
    local secondaryRgb = _NormalizeRgbColor(secondary)

    local primaryValue = primaryRgb or _ClampInt(primary, 0, 160, 0)
    local secondaryValue = secondaryRgb or _ClampInt(secondary, 0, 160, 0)

    TriggerClientEvent('lyxpanel:setVehicleColor', target, primaryValue, secondaryValue)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SET_VEHICLE_COLOR', GetId(target, 'license'), GetPlayerName(target),
        { primary = primaryValue, secondary = secondaryValue })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Color del vehiculo cambiado')
end)

-- Cambiar placa del vehiculo (max 8 chars, A-Z0-9)
RegisterNetEvent('lyxpanel:action:setVehiclePlate', function(targetId, plate)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end
    if _IsRateLimited(s, 'setVehiclePlate', _GetCooldownMs('setVehiclePlate', 1000)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target then return end

    plate = _NormalizePlateText(plate)
    if not plate then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Placa invalida')
        return
    end

    TriggerClientEvent('lyxpanel:setVehiclePlate', target, plate)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SET_VEHICLE_PLATE', GetId(target, 'license'), GetPlayerName(target),
        { plate = plate })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Placa aplicada')
end)

-- Tunear vehiculo al maximo
RegisterNetEvent('lyxpanel:action:tuneVehicle', function(targetId)
    local s = source
    if not HasPermission(s, 'canSpawnWithMods') then return end
    if _IsRateLimited(s, 'tuneVehicle', _GetCooldownMs('tuneVehicle', 1500)) then return end
    local target = _AsTargetPlayer(s, targetId)
    if not target then return end
    TriggerClientEvent('lyxpanel:tuneVehicle', target)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TUNE_VEHICLE', GetId(target, 'license'), GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Vehiculo tuneado al maximo')
end)

-- Modo fantasma (sin colisin) para vehiculos admin
RegisterNetEvent('lyxpanel:action:ghostVehicle', function(targetId, enabled)
    local s = source
    if not HasPermission(s, 'canNoclip') then return end -- Using noclip permission
    if _IsRateLimited(s, 'ghostVehicle', _GetCooldownMs('ghostVehicle', 500)) then return end
    local target = _AsTargetPlayer(s, targetId)
    if not target then return end
    enabled = _AsBool(enabled, false)
    TriggerClientEvent('lyxpanel:ghostVehicle', target, enabled)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GHOST_VEHICLE', GetId(target, 'license'), GetPlayerName(target),
        { enabled = enabled })
    TriggerClientEvent('lyxpanel:notify', s, 'success',
        enabled and 'Modo fantasma ACTIVADO' or 'Modo fantasma DESACTIVADO')
end)

-- Obtener informacin del vehiculo actual
RegisterNetEvent('lyxpanel:action:getVehicleInfo', function()
    local s = source
    if not HasPanelAccess(s) then return end
    if _IsRateLimited(s, 'getVehicleInfo', _GetCooldownMs('getVehicleInfo', 750)) then return end
    TriggerClientEvent('lyxpanel:getVehicleInfo', s)
end)

-- 
-- TELEPORT
-- 

RegisterNetEvent('lyxpanel:action:teleportTo', function(targetId)
    local s = source
    if not HasPermission(s, 'canGoto') then return end
    if _IsRateLimited(s, 'teleportTo', _GetCooldownMs('teleportTo', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador no encontrado')
        return
    end

    -- Handle self-targeting (cannot TP to yourself)
    local actualTarget = targetId
    if actualTarget == s then
        TriggerClientEvent('lyxpanel:notify', s, 'warning', 'No puedes teleportarte a ti mismo')
        return
    end

    local ped = GetPlayerPed(actualTarget)
    if ped and ped ~= 0 then
        local c = GetEntityCoords(ped)
        if c then
            _TryGuardSafe(s, { 'movement', 'teleport' }, _GetGuardSafeMs('movement', 5000))
            TriggerClientEvent('lyxpanel:teleport', s, c.x, c.y, c.z)
            TriggerClientEvent('lyxpanel:notify', s, 'success',
                'Teleportado a ' .. (GetPlayerName(actualTarget) or 'jugador'))
            LogAction(GetId(s, 'license'), GetPlayerName(s), 'GOTO', GetId(actualTarget, 'license'), GetPlayerName(actualTarget),
                { x = c.x, y = c.y, z = c.z })
        else
            TriggerClientEvent('lyxpanel:notify', s, 'error', 'No se pudo obtener coordenadas')
        end
    else
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador no encontrado o sin ped')
    end
end)

RegisterNetEvent('lyxpanel:action:bring', function(targetId)
    local s = source
    if not HasPermission(s, 'canBring') then return end
    if _IsRateLimited(s, 'bring', _GetCooldownMs('bring', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador no encontrado')
        return
    end
    if targetId == s then
        TriggerClientEvent('lyxpanel:notify', s, 'warning', 'No puedes traerte a ti mismo')
        return
    end

    local ped = GetPlayerPed(s)
    if not ped or ped == 0 then return end
    local c = GetEntityCoords(ped)
    if not c then return end

    _TryGuardSafe(targetId, { 'movement', 'teleport' }, _GetGuardSafeMs('movement', 5000))
    TriggerClientEvent('lyxpanel:teleport', targetId, c.x, c.y, c.z)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'BRING', GetId(targetId, 'license'), GetPlayerName(targetId),
        { x = c.x, y = c.y, z = c.z })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador traido')
    TriggerClientEvent('lyxpanel:notify', targetId, 'info', 'Trado por un admin')
end)

RegisterNetEvent('lyxpanel:action:teleportCoords', function(x, y, z)
    local s = source
    if not HasPermission(s, 'canTeleport') then return end
    if _IsRateLimited(s, 'teleportCoords', _GetCooldownMs('teleportCoords', 750)) then return end

    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Coords invalidas')
        return
    end
    if x < -20000 or x > 20000 or y < -20000 or y > 20000 or z < -2000 or z > 5000 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Coords fuera de rango')
        return
    end

    _TryGuardSafe(s, { 'movement', 'teleport' }, _GetGuardSafeMs('movement', 5000))
    TriggerClientEvent('lyxpanel:teleport', s, x, y, z)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TP_COORDS', GetId(s, 'license'), GetPlayerName(s), { x = x, y = y, z = z })
end)

RegisterNetEvent('lyxpanel:action:teleportMarker', function()
    local s = source
    if not HasPermission(s, 'canTeleport') then return end
    if _IsRateLimited(s, 'teleportMarker', _GetCooldownMs('teleportMarker', 750)) then return end
    TriggerClientEvent('lyxpanel:teleportMarker', s)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TP_MARKER', GetId(s, 'license'), GetPlayerName(s), {})
end)

-- SALUD (heal is already defined above at line 289)

RegisterNetEvent('lyxpanel:action:revive', function(targetId)
    local s = source
    DebugPrint('[LyxPanel] Action REVIVE requested by:', s, 'for target:', targetId)

    if not HasPermission(s, 'canRevive') then
        DebugPrint('[LyxPanel] REVIVE DENIED: Missing permission')
        return
    end
    if _IsRateLimited(s, 'revive', _GetCooldownMs('revive', 750)) then return end

    targetId = tonumber(targetId)
    local target = (targetId == -1 or not targetId) and s or targetId
    if not GetPlayerName(target) then return end
    DebugPrint('[LyxPanel] REVIVE executing for target:', target)

    _TryGuardSafe(target, { 'health' }, _GetGuardSafeMs('health', 3000))
    TriggerClientEvent('lyxpanel:revive', target)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'REVIVE', nil, GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador revivido')
end)

RegisterNetEvent('lyxpanel:action:setArmor', function(targetId, amount)
    local s = source
    if not HasPermission(s, 'canGiveArmor') then return end
    if _IsRateLimited(s, 'setArmor', _GetCooldownMs('setArmor', 750)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target then return end

    local a = _AsInt(amount, 100)
    if a < 0 then a = 0 end
    if a > 100 then a = 100 end
    _TryGuardSafe(target, { 'health' }, _GetGuardSafeMs('health', 3000))
    TriggerClientEvent('lyxpanel:setArmor', target, a)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SET_ARMOR', GetId(target, 'license'), GetPlayerName(target), { armor = a })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Armadura establecida')
end)

RegisterNetEvent('lyxpanel:action:setHealth', function(targetId, amount)
    local s = source
    if not HasPermission(s, 'canHeal') then return end
    if _IsRateLimited(s, 'setHealth', _GetCooldownMs('setHealth', 750)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target then return end

    local h = _AsInt(amount, 200)
    if h < 1 then h = 1 end
    if h > 200 then h = 200 end
    _TryGuardSafe(target, { 'health' }, _GetGuardSafeMs('health', 3000))
    TriggerClientEvent('lyxpanel:setHealth', target, h)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SET_HEALTH', GetId(target, 'license'), GetPlayerName(target), { health = h })
end)

-- 
-- CONTROL
-- 

RegisterNetEvent('lyxpanel:action:freeze', function(targetId, freeze)
    local s = source
    if not HasPermission(s, 'canFreeze') then return end
    if _IsRateLimited(s, 'freeze', _GetCooldownMs('freeze', 750)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target then return end

    local frz = (freeze == true) or (tostring(freeze) == 'true') or (tonumber(freeze) == 1)
    TriggerClientEvent('lyxpanel:freeze', target, frz)
    LogAction(GetId(s, 'license'), GetPlayerName(s), frz and 'FREEZE' or 'UNFREEZE', GetId(target, 'license'), GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', frz and 'Congelado' or 'Descongelado')
end)

RegisterNetEvent('lyxpanel:action:spectate', function(targetId)
    local s = source
    if not HasPermission(s, 'canSpectate') then return end
    if _IsRateLimited(s, 'spectate', _GetCooldownMs('spectate', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    if targetId == s then return end

    if not GetPlayerName(targetId) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador no encontrado')
        return
    end

    local staffBucket = GetPlayerRoutingBucket(s)
    local targetBucket = GetPlayerRoutingBucket(targetId)

    local session = SpectateSessions[s]
    if not session then
        SpectateSessions[s] = {
            originalBucket = staffBucket,
            targetId = targetId,
        }
    else
        session.targetId = targetId
    end

    SetPlayerRoutingBucket(s, targetBucket)

    local c = GetEntityCoords(GetPlayerPed(targetId))
    TriggerClientEvent('lyxpanel:spectate:start', s, targetId, c)
end)

RegisterNetEvent('lyxpanel:action:kill', function(targetId)
    local s = source
    if not HasPermission(s, 'canKill') then return end
    if _IsRateLimited(s, 'kill', _GetCooldownMs('kill', 750)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target or target == s then
        TriggerClientEvent('lyxpanel:notify', s, 'warning', 'Target invalido')
        return
    end

    TriggerClientEvent('lyxpanel:kill', target)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'KILL', GetId(target, 'license'), GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador eliminado')
end)

RegisterNetEvent('lyxpanel:action:slap', function(targetId)
    local s = source
    if not HasPermission(s, 'canSlap') then return end
    if _IsRateLimited(s, 'slap', _GetCooldownMs('slap', 750)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target or target == s then
        TriggerClientEvent('lyxpanel:notify', s, 'warning', 'Target invalido')
        return
    end

    TriggerClientEvent('lyxpanel:slap', target)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SLAP', GetId(target, 'license'), GetPlayerName(target), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador golpeado')
    TriggerClientEvent('lyxpanel:notify', target, 'warning', 'Has sido golpeado por un admin')
end)

RegisterNetEvent('lyxpanel:action:ragdoll', function(targetId, durationMs)
    local s = source
    if not HasPermission(s, 'canSlap') then return end -- reuse "slap" perm for troll actions
    if _IsRateLimited(s, 'ragdoll', _GetCooldownMs('ragdoll', 750)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target or target == s then
        TriggerClientEvent('lyxpanel:notify', s, 'warning', 'Target invalido')
        return
    end

    durationMs = _ClampInt(durationMs, 500, 15000, 5000)
    TriggerClientEvent('lyxpanel:ragdoll', target, durationMs)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'RAGDOLL', GetId(target, 'license'), GetPlayerName(target),
        { durationMs = durationMs })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Ragdoll aplicado')
    TriggerClientEvent('lyxpanel:notify', target, 'warning', 'Has sido ragdolleado por un admin')
end)


-- 
-- TRABAJO
-- 

RegisterNetEvent('lyxpanel:action:setJob', function(targetId, job, grade)
    local s = source
    if not HasPermission(s, 'canSetJob') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'setJob', _GetCooldownMs('setJob', 1000)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador invalido')
        return
    end

    job = tostring(job or ''):lower():gsub('%s+', '')
    if #job < 1 or #job > 32 or job:match('^[%w_]+$') == nil then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Trabajo invalido')
        return
    end

    local g = _AsInt(grade, 0)
    if g < 0 then g = 0 end
    if g > 99 then g = 99 end

    if ESX.DoesJobExist and not ESX.DoesJobExist(job, g) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Trabajo/grade no existe')
        return
    end

    local xT = ESX.GetPlayerFromId(target)
    if not xT or not xT.setJob then return end

    xT.setJob(job, g)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SET_JOB', xT.identifier, GetPlayerName(target),
        { job = job, grade = g })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Trabajo asignado')
end)

-- 
-- ADMIN TOOLS
-- 

RegisterNetEvent('lyxpanel:action:noclip', function()
    local s = source
    if not HasPermission(s, 'canNoclip') then return end
    if _IsRateLimited(s, 'noclip', _GetCooldownMs('noclip', 250)) then return end
    TriggerClientEvent('lyxpanel:toggleNoclip', s)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'NOCLIP', GetId(s, 'license'), GetPlayerName(s), {})
end)

RegisterNetEvent('lyxpanel:action:godmode', function()
    local s = source
    if not HasPermission(s, 'canGodmode') then return end
    if _IsRateLimited(s, 'godmode', _GetCooldownMs('godmode', 250)) then return end
    TriggerClientEvent('lyxpanel:toggleGodmode', s)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GODMODE', GetId(s, 'license'), GetPlayerName(s), {})
end)

RegisterNetEvent('lyxpanel:action:invisible', function()
    local s = source
    if not HasPermission(s, 'canInvisible') then return end
    if _IsRateLimited(s, 'invisible', _GetCooldownMs('invisible', 250)) then return end
    TriggerClientEvent('lyxpanel:toggleInvisible', s)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'INVISIBLE', GetId(s, 'license'), GetPlayerName(s), {})
end)

RegisterNetEvent('lyxpanel:action:speedboost', function()
    local s = source
    if not HasPermission(s, 'canGodmode') then return end -- Using godmode permission
    if _IsRateLimited(s, 'speedboost', _GetCooldownMs('speedboost', 250)) then return end
    TriggerClientEvent('lyxpanel:toggleSpeedboost', s)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SPEEDBOOST', GetId(s, 'license'), GetPlayerName(s), {})
end)

RegisterNetEvent('lyxpanel:action:nitro', function()
    local s = source
    if not HasPermission(s, 'canGodmode') then return end -- Using godmode permission
    if _IsRateLimited(s, 'nitro', _GetCooldownMs('nitro', 250)) then return end
    TriggerClientEvent('lyxpanel:toggleNitro', s)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'NITRO', GetId(s, 'license'), GetPlayerName(s), {})
end)

RegisterNetEvent('lyxpanel:action:vehicleGodmode', function()
    local s = source
    if not HasPermission(s, 'canGodmode') then return end -- Using godmode permission
    if _IsRateLimited(s, 'vehicleGodmode', _GetCooldownMs('vehicleGodmode', 250)) then return end
    TriggerClientEvent('lyxpanel:toggleVehicleGodmode', s)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_GODMODE', GetId(s, 'license'), GetPlayerName(s), {})
end)

-- 
-- COMUNICACIN
-- 

RegisterNetEvent('lyxpanel:action:announce', function(message, type)
    local s = source
    if not HasPermission(s, 'canAnnounce') then return end
    if _IsRateLimited(s, 'announce', _GetCooldownMs('announce', 1500)) then return end

    local msgMax = _GetLimitNumber('maxAnnouncementLength', 250)
    message = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(message or '', msgMax)) or tostring(message or '')
    message = message:match('^%s*(.-)%s*$') or message
    if message == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Mensaje invalido')
        return
    end

    type = tostring(type or 'info'):lower()
    local allowedType = { info = true, success = true, warning = true, error = true }
    if not allowedType[type] then type = 'info' end

    TriggerClientEvent('lyxpanel:announce', -1, message, type)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'ANNOUNCE', nil, nil, { message = message, type = type })
end)

RegisterNetEvent('lyxpanel:action:privateMessage', function(targetId, message)
    local s = source
    if not HasPermission(s, 'canPrivateChat') then return end
    if _IsRateLimited(s, 'privateMessage', _GetCooldownMs('privateMessage', 750)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target then return end

    local msgMax = math.max(_GetLimitNumber('maxAnnouncementLength', 250), 400)
    message = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(message or '', msgMax)) or tostring(message or '')
    message = message:match('^%s*(.-)%s*$') or message
    if message == '' then return end

    TriggerClientEvent('lyxpanel:privateMessage', target, GetPlayerName(s), message)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'PRIVATE_MESSAGE', GetId(target, 'license'), GetPlayerName(target),
        { message = message })
end)

RegisterNetEvent('lyxpanel:action:adminChat', function(message)
    local s = source
    if not HasPermission(s, 'canAdminChat') then return end
    if _IsRateLimited(s, 'adminChat', _GetCooldownMs('adminChat', 750)) then return end

    local msgMax = math.max(_GetLimitNumber('maxAnnouncementLength', 250), 400)
    message = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(message or '', msgMax)) or tostring(message or '')
    message = message:match('^%s*(.-)%s*$') or message
    if message == '' then return end

    for _, playerId in ipairs(GetPlayers()) do
        if HasPanelAccess(tonumber(playerId)) then
            TriggerClientEvent('lyxpanel:adminChat', tonumber(playerId), GetPlayerName(s), message)
        end
    end
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'ADMIN_CHAT', nil, nil, { message = message })
end)

-- 
-- NOTAS
-- 

RegisterNetEvent('lyxpanel:action:addNote', function(targetId, note)
    local s = source
    if not HasPermission(s, 'canAddNotes') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'addNote', _GetCooldownMs('addNote', 750)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target then return end

    local xT = ESX.GetPlayerFromId(target)
    if not xT then return end

    local noteMax = math.max(_GetLimitNumber('maxReasonLength', 200), 400)
    note = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(note or '', noteMax)) or tostring(note or '')
    note = note:match('^%s*(.-)%s*$') or note
    if note == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Nota vacia')
        return
    end

    MySQL.insert(
        'INSERT INTO lyxpanel_notes (target_id, note, admin_id, admin_name) VALUES (?,?,?,?)',
        { xT.identifier, note, GetId(s, 'license'), GetPlayerName(s) })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'ADD_NOTE', xT.identifier, GetPlayerName(target), { note = note })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Nota anadida')
end)

-- 
-- MUNDO
-- 

RegisterNetEvent('lyxpanel:action:setWeather', function(weather)
    local s = source
    if not HasPermission(s, 'canChangeWeather') then return end
    if _IsRateLimited(s, 'setWeather', _GetCooldownMs('setWeather', 1500)) then return end

    weather = tostring(weather or ''):upper():match('^%s*(.-)%s*$')
    if not weather or weather == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Clima invalido')
        return
    end

    local allowed = {}
    local types = Config and Config.Weather and Config.Weather.types or {}
    for _, t in ipairs(types) do
        allowed[t] = true
    end
    if next(allowed) and not allowed[weather] then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Clima no permitido')
        return
    end

    TriggerClientEvent('lyxpanel:setWeather', -1, weather)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SET_WEATHER', '', '', { weather = weather })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Clima: ' .. weather)
end)

RegisterNetEvent('lyxpanel:action:setTime', function(hour, minute)
    local s = source
    if not HasPermission(s, 'canChangeTime') then return end
    if _IsRateLimited(s, 'setTime', _GetCooldownMs('setTime', 1500)) then return end

    hour = _AsInt(hour, 12)
    minute = _AsInt(minute, 0)
    if hour < 0 then hour = 0 end
    if hour > 23 then hour = 23 end
    if minute < 0 then minute = 0 end
    if minute > 59 then minute = 59 end

    TriggerClientEvent('lyxpanel:setTime', -1, hour, minute)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'SET_TIME', '', '', { hour = hour, minute = minute })
    TriggerClientEvent('lyxpanel:notify', s, 'success', ('Hora: %02d:%02d'):format(hour, minute))
end)

-- 
-- REPORTES / BANS
-- 

RegisterNetEvent('lyxpanel:action:assignReport', function(reportId)
    local s = source
    if not HasPermission(s, 'canAssignReport') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'assignReport', _GetCooldownMs('assignReport', 750)) then return end

    reportId = _AsInt(reportId, 0)
    if reportId <= 0 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Reporte invalido')
        return
    end

    local xP = ESX.GetPlayerFromId(s)
    if xP then
        MySQL.update("UPDATE lyxpanel_reports SET status = 'in_progress', assigned_to = ? WHERE id = ? AND status = 'open'",
            { xP.identifier, reportId }, function(affected)
                local ok = affected and affected > 0
                if ok then
                    LogAction(GetId(s, 'license'), GetPlayerName(s), 'REPORT_ASSIGN', tostring(reportId), '',
                        { reportId = reportId, assigned_to = xP.identifier })
                    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Reporte asignado')
                else
                    TriggerClientEvent('lyxpanel:notify', s, 'error', 'Reporte no encontrado o ya atendido')
                end
            end)
    end
end)

RegisterNetEvent('lyxpanel:action:closeReport', function(reportId, notes)
    local s = source
    if not HasPermission(s, 'canManageReports') then return end
    if _IsRateLimited(s, 'closeReport', _GetCooldownMs('closeReport', 1000)) then return end

    reportId = _AsInt(reportId, 0)
    if reportId <= 0 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Reporte invalido')
        return
    end

    local notesMax = _GetLimitNumber('maxAnnouncementLength', 250)
    notes = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(notes or '', notesMax)) or tostring(notes or '')
    notes = notes:match('^%s*(.-)%s*$') or notes

    MySQL.update("UPDATE lyxpanel_reports SET status = 'closed' WHERE id = ? AND status IN ('open','in_progress')",
        { reportId },
        function(affected)
            local ok = affected and affected > 0
            if ok then
                LogAction(GetId(s, 'license'), GetPlayerName(s), 'REPORT_CLOSE', tostring(reportId), '',
                    { reportId = reportId, notes = notes })
                TriggerClientEvent('lyxpanel:notify', s, 'success', 'Reporte cerrado')
            else
                TriggerClientEvent('lyxpanel:notify', s, 'error', 'Reporte no encontrado o ya cerrado')
            end
        end)
end)

RegisterNetEvent('lyxpanel:action:setReportPriority', function(reportId, priority)
    local s = source
    if not HasPermission(s, 'canPriorityReport') then return end
    if _IsRateLimited(s, 'setReportPriority', _GetCooldownMs('setReportPriority', 750)) then return end

    reportId = _AsInt(reportId, 0)
    if reportId <= 0 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Reporte invalido')
        return
    end

    priority = tostring(priority or ''):lower():match('^%s*(.-)%s*$')
    local allowed = { low = true, medium = true, high = true, urgent = true }
    if not allowed[priority] then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Prioridad invalida')
        return
    end

    MySQL.update('UPDATE lyxpanel_reports SET priority = ? WHERE id = ?', { priority, reportId }, function()
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'REPORT_PRIORITY', tostring(reportId), '',
            { reportId = reportId, priority = priority })
        TriggerClientEvent('lyxpanel:notify', s, 'success', 'Prioridad actualizada')
    end)
end)

-- 
-- MODELO
-- 

RegisterNetEvent('lyxpanel:action:changeModel', function(targetId, model)
    local s = source
    if not HasPermission(s, 'canChangeModel') then return end
    if _IsRateLimited(s, 'changeModel', _GetCooldownMs('changeModel', 1500)) then return end

    local target = _AsTargetPlayer(s, targetId)
    if not target then return end

    local maxLen = 32
    model = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(model or '', maxLen)) or tostring(model or '')
    model = model:match('^%s*(.-)%s*$') or model
    if model == '' or #model > maxLen or model:match('^[%w_]+$') == nil then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Modelo invalido')
        return
    end

    TriggerClientEvent('lyxpanel:changeModel', target, model)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'CHANGE_MODEL', GetId(target, 'license'), GetPlayerName(target), { model = model })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Modelo cambiado')
end)

-- 
-- SCREENSHOT
-- 

RegisterNetEvent('lyxpanel:action:screenshot', function(targetId)
    local s = source
    if not HasPermission(s, 'canScreenshot') then return end
    if _IsRateLimited(s, 'screenshot', _GetCooldownMs('screenshot', 5000)) then return end
    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    if GetResourceState('screenshot-basic') ~= 'started' or not exports['screenshot-basic'] then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'screenshot-basic no esta instalado/iniciado (funcion desactivada)')
        return
    end

    exports['screenshot-basic']:requestClientScreenshot(targetId, { encoding = 'png', quality = 0.8 },
        function(err, data)
            if err then
                TriggerClientEvent('lyxpanel:notify', s, 'error', 'Error al tomar captura')
                return
            end
            LogAction(GetId(s, 'license'), GetPlayerName(s), 'SCREENSHOT', GetId(targetId, 'license'), GetPlayerName(targetId),
                { ok = true })
            TriggerClientEvent('lyxpanel:notify', s, 'success', 'Captura tomada')
        end)
end)

-- 
-- FUNCIONES DE TROLLEO (12 NUEVAS)
-- 

-- Explosin visual sin dao
RegisterNetEvent('lyxpanel:action:troll:explode', function(targetId)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_explode', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    TriggerClientEvent('lyxpanel:troll:explode', targetId)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_EXPLODE', GetId(targetId, 'license'), name, {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Explosion activada')
end)

-- Prender fuego al jugador
RegisterNetEvent('lyxpanel:action:troll:fire', function(targetId)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_fire', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    TriggerClientEvent('lyxpanel:troll:fire', targetId)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_FIRE', GetId(targetId, 'license'), name, {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Fuego activado')
end)

-- Lanzar al jugador al aire
-- NOTA: Evento movido a lnea 945 con soporte para parmetro 'force'

-- Hacer ragdoll al jugador
RegisterNetEvent('lyxpanel:action:troll:ragdoll', function(targetId)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_ragdoll', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    TriggerClientEvent('lyxpanel:troll:ragdoll', targetId)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_RAGDOLL', GetId(targetId, 'license'), name, {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Ragdoll activado')
end)

-- Efecto de borracho
RegisterNetEvent('lyxpanel:action:troll:drunk', function(targetId, duration)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_drunk', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    duration = _AsInt(duration, 30)
    if duration < 1 then duration = 1 end
    if duration > 300 then duration = 300 end
    TriggerClientEvent('lyxpanel:troll:drunk', targetId, duration)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_DRUNK', GetId(targetId, 'license'), name,
        { duration = duration })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Borracho por ' .. duration .. 's')
end)

-- Pantalla de drogas
RegisterNetEvent('lyxpanel:action:troll:drugScreen', function(targetId, duration)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_drug', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    duration = _AsInt(duration, 20)
    if duration < 1 then duration = 1 end
    if duration > 300 then duration = 300 end
    TriggerClientEvent('lyxpanel:troll:drugScreen', targetId, duration)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_DRUG', GetId(targetId, 'license'), name,
        { duration = duration })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Drogas por ' .. duration .. 's')
end)

-- Pantalla negra temporal
RegisterNetEvent('lyxpanel:action:troll:blackScreen', function(targetId, duration)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_blackscreen', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    duration = _AsInt(duration, 10)
    if duration < 1 then duration = 1 end
    if duration > 60 then duration = 60 end
    TriggerClientEvent('lyxpanel:troll:blackScreen', targetId, duration)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_BLACKSCREEN', GetId(targetId, 'license'), name,
        { duration = duration })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Pantalla negra por ' .. duration .. 's')
end)

-- Sonido de susto
RegisterNetEvent('lyxpanel:action:troll:scream', function(targetId)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_scream', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    TriggerClientEvent('lyxpanel:troll:scream', targetId)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_SCREAM', GetId(targetId, 'license'), name, {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Sonido de susto')
end)

-- Teleport aleatorio
RegisterNetEvent('lyxpanel:action:troll:randomTeleport', function(targetId)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_randomtp', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    local locations = {
        vector3(-1037.0, -2737.0, 20.2), -- Aeropuerto
        vector3(1827.0, 3693.0, 34.3),   -- Sandy Shores
        vector3(-379.0, 6118.0, 31.5),   -- Paleto Bay
        vector3(3580.0, 3655.0, 33.0),   -- Desierto
        vector3(-1820.0, -1220.0, 13.0), -- Muelle
        vector3(123.0, 6630.0, 31.0),    -- Norte
        vector3(-2240.0, 260.0, 175.0),  -- Montaa
    }
    local randomLoc = locations[math.random(#locations)]
    TriggerClientEvent('lyxpanel:troll:teleport', targetId, randomLoc.x, randomLoc.y, randomLoc.z)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_RANDOMTP', GetId(targetId, 'license'), name,
        { x = randomLoc.x, y = randomLoc.y, z = randomLoc.z })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Teleportado aleatoriamente')
end)

-- Quitar ropa
RegisterNetEvent('lyxpanel:action:troll:stripClothes', function(targetId)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_strip', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    TriggerClientEvent('lyxpanel:troll:strip', targetId)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_STRIP', GetId(targetId, 'license'), name, {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Ropa quitada')
end)

-- Invertir controles
RegisterNetEvent('lyxpanel:action:troll:invertControls', function(targetId, duration)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_invert', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    duration = _AsInt(duration, 15)
    if duration < 1 then duration = 1 end
    if duration > 300 then duration = 300 end
    TriggerClientEvent('lyxpanel:troll:invert', targetId, duration)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_INVERT', GetId(targetId, 'license'), name,
        { duration = duration })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Controles invertidos por ' .. duration .. 's')
end)

-- Cambiar a ped aleatorio
RegisterNetEvent('lyxpanel:action:troll:randomPed', function(targetId)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_randomped', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    local peds = { 'a_m_m_bevhills_01', 'a_f_m_beach_01', 'a_m_m_skater_01', 's_m_m_clown_01', 'u_m_y_zombie_01',
        'a_m_m_homeless_01', 's_m_o_busker_01', 'a_f_y_hiker_01' }
    local randomPed = peds[math.random(#peds)]
    TriggerClientEvent('lyxpanel:troll:randomPed', targetId, randomPed)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_RANDOMPED', GetId(targetId, 'license'), name,
        { ped = randomPed })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Modelo cambiado a: ' .. randomPed)
end)

-- Pollo (convertir en pollo)
RegisterNetEvent('lyxpanel:action:troll:chicken', function(targetId)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_chicken', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    TriggerClientEvent('lyxpanel:troll:randomPed', targetId, 'a_c_chicken')
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_CHICKEN', GetId(targetId, 'license'), name, {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Convertido en pollo')
end)

-- Hacer bailar
RegisterNetEvent('lyxpanel:action:troll:dance', function(targetId)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_dance', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    TriggerClientEvent('lyxpanel:troll:dance', targetId)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_DANCE', GetId(targetId, 'license'), name, {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Bailando')
end)

-- 
-- NUEVOS TROLLS AVANZADOS
-- 

-- Invisible (solo para l)
RegisterNetEvent('lyxpanel:action:troll:invisible', function(targetId, duration)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_invisible', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    duration = _AsInt(duration, 30)
    if duration < 1 then duration = 1 end
    if duration > 300 then duration = 300 end
    TriggerClientEvent('lyxpanel:troll:invisible', targetId, duration)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_INVISIBLE', GetId(targetId, 'license'), name,
        { duration = duration })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Invisible por ' .. duration .. 's')
end)

-- Spin (girar sin control)
RegisterNetEvent('lyxpanel:action:troll:spin', function(targetId, duration)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_spin', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    duration = _AsInt(duration, 15)
    if duration < 1 then duration = 1 end
    if duration > 120 then duration = 120 end
    TriggerClientEvent('lyxpanel:troll:spin', targetId, duration)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_SPIN', GetId(targetId, 'license'), name,
        { duration = duration })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Girando por ' .. duration .. 's')
end)

-- Shrink (hacer enano)
RegisterNetEvent('lyxpanel:action:troll:shrink', function(targetId, duration)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_shrink', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    duration = _AsInt(duration, 60)
    if duration < 1 then duration = 1 end
    if duration > 600 then duration = 600 end
    TriggerClientEvent('lyxpanel:troll:shrink', targetId, duration)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_SHRINK', GetId(targetId, 'license'), name,
        { duration = duration })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Encogido por ' .. duration .. 's')
end)

-- Giant (hacer gigante)
RegisterNetEvent('lyxpanel:action:troll:giant', function(targetId, duration)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_giant', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    duration = _AsInt(duration, 30)
    if duration < 1 then duration = 1 end
    if duration > 300 then duration = 300 end
    TriggerClientEvent('lyxpanel:troll:giant', targetId, duration)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_GIANT', GetId(targetId, 'license'), name,
        { duration = duration })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Gigante por ' .. duration .. 's')
end)

-- Clone Army (spawnar clones)
RegisterNetEvent('lyxpanel:action:troll:clones', function(targetId, count)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_clones', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    count = _AsInt(count, 5)
    if count < 1 then count = 1 end
    if count > 10 then count = 10 end
    TriggerClientEvent('lyxpanel:troll:clones', targetId, count)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_CLONES', GetId(targetId, 'license'), name, { count = count })
    TriggerClientEvent('lyxpanel:notify', s, 'success', count .. ' clones atacando')
end)

-- Launch (lanzar al aire)
RegisterNetEvent('lyxpanel:action:troll:launch', function(targetId, force)
    local s = source
    if not HasPermission(s, 'canTroll') then return end
    if _IsRateLimited(s, 'troll_launch', _GetCooldownMs('trollAction', 750)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end
    local name = GetPlayerName(targetId)
    if not name then return end
    force = tonumber(force) or 50.0
    if force < 1.0 then force = 1.0 end
    if force > 200.0 then force = 200.0 end
    TriggerClientEvent('lyxpanel:troll:launch', targetId, force)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TROLL_LAUNCH', GetId(targetId, 'license'), name, { force = force })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Lanzado al aire!')
end)

-- NUEVAS ACCIONES v4.0
-- 

-- Limpiar todas las detecciones (LyxGuard) - DANGEROUS
RegisterNetEvent('lyxpanel:action:clearAllDetections', function(reason, dryRun)
    local s = source
    if not HasPermission(s, 'canManageDetections') then return end

    if _IsRateLimited(s, 'clearAllDetections', _GetCooldownMs('clearAllDetections', 30000)) then return end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    reason = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(reason or '', reasonMax)) or tostring(reason or '')
    reason = reason:match('^%s*(.-)%s*$') or reason
    if reason == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Motivo obligatorio')
        return
    end

    if not (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'lyx-guard no esta activo')
        return
    end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_ALL_DETECTIONS', '', '', { reason = reason, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] Clear detections simulado (no ejecutado)')
        return
    end

    MySQL.update('TRUNCATE TABLE lyxguard_detections', {}, function()
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_ALL_DETECTIONS', '', '', { reason = reason })
        TriggerClientEvent('lyxpanel:notify', s, 'success', 'Detecciones limpiadas')
    end)
end)

-- Limpiar logs
RegisterNetEvent('lyxpanel:action:clearLogs', function(reason, dryRun)
    local s = source

    local ok, group = HasPanelAccess(s)
    local fullAccessGroups = { superadmin = true, master = true, owner = true }
    if not ok or not fullAccessGroups[group] then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Sin permisos para borrar logs')
        return
    end

    if _IsRateLimited(s, 'clearLogs', _GetCooldownMs('clearLogs', 30000)) then return end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    reason = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(reason or '', reasonMax)) or tostring(reason or '')
    reason = reason:match('^%s*(.-)%s*$') or reason
    if reason == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Motivo obligatorio')
        return
    end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_LOGS', '', '', { reason = reason, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] Clear logs simulado (no ejecutado)')
        return
    end

    MySQL.update('TRUNCATE TABLE lyxpanel_logs', {}, function()
        -- Keep a record of who cleared logs by inserting after truncation.
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_LOGS', '', '', { reason = reason })
        TriggerClientEvent('lyxpanel:notify', s, 'success', 'Logs borrados')
    end)
end)

-- Teleportar al reporter
RegisterNetEvent('lyxpanel:action:tpToReporter', function(reporterId)
    local s = source
    if not HasPermission(s, 'canManageReports') then return end
    if _IsRateLimited(s, 'tpToReporter', _GetCooldownMs('tpToReporter', 1000)) then return end

    local idMax = 255
    reporterId = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(reporterId or '', idMax)) or
        tostring(reporterId or '')
    reporterId = reporterId:match('^%s*(.-)%s*$') or reporterId
    if reporterId == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Reporter invalido')
        return
    end

    -- Find the reporter by their identifier or source
    local reporterSource = nil

    for _, playerId in ipairs(GetPlayers()) do
        if GetPlayerName(playerId) then
            local playerLicense = GetId(tonumber(playerId), 'license')
            if playerLicense == reporterId or tostring(playerId) == tostring(reporterId) then
                reporterSource = tonumber(playerId)
                break
            end
        end
    end

    if reporterSource then
        local reporterPed = GetPlayerPed(reporterSource)
        if reporterPed and DoesEntityExist(reporterPed) then
            local coords = GetEntityCoords(reporterPed)
            _TryGuardSafe(s, { 'movement', 'teleport' }, _GetGuardSafeMs('movement', 5000))
            TriggerClientEvent('lyxpanel:teleport', s, coords.x, coords.y, coords.z)
            TriggerClientEvent('lyxpanel:notify', s, 'success', 'Teleportado al reporter')
        else
            TriggerClientEvent('lyxpanel:notify', s, 'error', 'No se pudo obtener posicion del reporter')
        end
    else
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Reporter no encontrado online')
    end
end)

-- Enviar mensaje de reporte (admin -> usuario)
RegisterNetEvent('lyxpanel:action:sendReportMessage', function(reportId, targetId, message)
    local s = source
    if not HasPermission(s, 'canManageReports') then return end
    if _IsRateLimited(s, 'sendReportMessage', _GetCooldownMs('sendReportMessage', 750)) then return end

    reportId = _AsInt(reportId, 0)
    if reportId <= 0 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Reporte invalido')
        return
    end

    if message == nil and type(targetId) == 'string' then
        message = targetId
        targetId = nil
    end

    if type(message) ~= 'string' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Mensaje invalido')
        return
    end
    local msgMax = math.max(_GetLimitNumber('maxAnnouncementLength', 250), 500)
    message = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(message, msgMax)) or tostring(message or '')
    message = message:match('^%s*(.-)%s*$') or message
    if message == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Mensaje vacio')
        return
    end

    MySQL.query('SELECT reporter_id FROM lyxpanel_reports WHERE id = ? LIMIT 1', { reportId }, function(result)
        local reporterId = result and result[1] and result[1].reporter_id or nil
        if not reporterId or reporterId == '' then
            TriggerClientEvent('lyxpanel:notify', s, 'error', 'Reporte no encontrado')
            return
        end

        MySQL.insert(
            'INSERT INTO lyxpanel_report_messages (report_id, sender_id, sender_name, message, is_admin) VALUES (?, ?, ?, ?, ?)',
            { reportId, GetId(s, 'license'), GetPlayerName(s), message, 1 })

        if targetId and GetPlayerName(targetId) then
            TriggerClientEvent('lyxpanel:privateMessage', targetId, GetPlayerName(s), message, 'report')
        end

        if reporterId then
            for _, playerId in ipairs(GetPlayers()) do
                local pid = tonumber(playerId)
                if pid and GetPlayerName(pid) then
                    local playerLicense = GetId(pid, 'license')
                    if playerLicense == reporterId then
                        TriggerClientEvent('lyxpanel:notify', pid, 'info', 'Respuesta del admin: ' .. message)
                        TriggerClientEvent('lyxpanel:playSound', pid, 'report')
                        break
                    end
                end
            end
        end

        TriggerClientEvent('lyxpanel:notify', s, 'success', 'Mensaje enviado')
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'REPORT_MESSAGE', tostring(reportId), '',
            { reportId = reportId, message = message })
    end)
end)

-- Obtener mensajes de un reporte (ESX Callback)
CreateThread(function()
    if not ESX and LyxPanel and LyxPanel.WaitForESX then
        ESX = LyxPanel.WaitForESX(15000)
    end
    if not ESX then return end
    ESX.RegisterServerCallback('lyxpanel:getReportMessages', function(source, cb, reportId)
        if not HasPermission(source, 'canManageReports') then
            cb({})
            return
        end
        reportId = tonumber(reportId)
        if not reportId then
            cb({}); return
        end
        MySQL.query('SELECT * FROM lyxpanel_report_messages WHERE report_id = ? ORDER BY created_at ASC', { reportId },
            function(result) cb(result or {}) end)
    end)
end)

-- Whitelist - Anadir
RegisterNetEvent('lyxpanel:action:addWhitelist', function(identifier, playerName)
    local s = source
    if not HasPermission(s, 'canManageWhitelist') then return end
    if _IsRateLimited(s, 'addWhitelist', _GetCooldownMs('addWhitelist', 1000)) then return end
    if not identifier then return end

    identifier = tostring(identifier or ''):gsub('%s+', '')
    if not _IsValidPanelIdentifier(identifier) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Identifier invalido')
        return
    end

    local nameMax = _GetLimitNumber('maxPlayerNameLength', 100)
    playerName = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(playerName or '', nameMax)) or
        tostring(playerName or '')
    playerName = playerName:match('^%s*(.-)%s*$') or playerName
    if playerName == '' then
        playerName = 'Desconocido'
    end

    local adminName = GetPlayerName(s) or 'Unknown'

    MySQL.query([[
        INSERT INTO lyxpanel_whitelist (identifier, name, player_name, added_by)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            name = VALUES(name),
            player_name = VALUES(player_name),
            added_by = VALUES(added_by)
    ]], { identifier, playerName, playerName, adminName })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'WHITELIST_ADD', identifier, '', {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Anadido a whitelist')
end)

-- Whitelist - Eliminar
RegisterNetEvent('lyxpanel:action:removeWhitelist', function(idOrIdentifier)
    local s = source
    if not HasPermission(s, 'canManageWhitelist') then return end
    if _IsRateLimited(s, 'removeWhitelist', _GetCooldownMs('removeWhitelist', 1000)) then return end

    if idOrIdentifier == nil then return end

    local id = tonumber(idOrIdentifier)
    if id then
        MySQL.update('DELETE FROM lyxpanel_whitelist WHERE id = ?', { id })
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'WHITELIST_REMOVE', '', '', { id = id })
        TriggerClientEvent('lyxpanel:notify', s, 'success', 'Eliminado de whitelist')
        return
    end

    local identifier = tostring(idOrIdentifier)
    if identifier == '' then return end
    identifier = identifier:gsub('%s+', '')
    if not _IsValidPanelIdentifier(identifier) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Identifier invalido')
        return
    end

    MySQL.update('DELETE FROM lyxpanel_whitelist WHERE identifier = ?', { identifier })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'WHITELIST_REMOVE', identifier, '', {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Eliminado de whitelist')
end)

-- Obtener whitelist (ESX Callback)
CreateThread(function()
    if not ESX and LyxPanel and LyxPanel.WaitForESX then
        ESX = LyxPanel.WaitForESX(15000)
    end
    if not ESX then return end
    ESX.RegisterServerCallback('lyxpanel:getWhitelist', function(source, cb)
        if not HasPermission(source, 'canManageWhitelist') then
            cb({})
            return
        end
        MySQL.query('SELECT * FROM lyxpanel_whitelist ORDER BY created_at DESC', {}, function(result)
            cb(result or {})
        end)
    end)
end)

-- Buscar jugadores (ESX Callback)
CreateThread(function()
    if not ESX and LyxPanel and LyxPanel.WaitForESX then
        ESX = LyxPanel.WaitForESX(15000)
    end
    if not ESX then return end
    ESX.RegisterServerCallback('lyxpanel:searchPlayers', function(source, cb, query)
        if type(HasPanelAccess) == 'function' then
            if not HasPanelAccess(source) then
                cb({}); return
            end
        end
        if not query or #query < 2 then
            cb({}); return
        end
        local searchQuery = '%' .. query .. '%'
        MySQL.query([[
            SELECT
                u.identifier,
                CONCAT(u.firstname, ' ', u.lastname) as name,
                u.job,
                (SELECT COUNT(*) FROM lyxguard_bans WHERE identifier = u.identifier) as ban_count,
                (SELECT COUNT(*) FROM lyxpanel_logs WHERE target_id = u.identifier AND action = 'WARN') as warn_count,
                (SELECT COUNT(*) FROM lyxpanel_logs WHERE target_id = u.identifier AND action = 'KICK') as kick_count
            FROM users u
            WHERE u.identifier LIKE ? OR u.firstname LIKE ? OR u.lastname LIKE ?
            LIMIT 20
        ]], { searchQuery, searchQuery, searchQuery }, function(result)
            cb(result or {})
        end)
    end)
end)

-- 
-- v4.2 - NEW FEATURES (From Analyzed Admin Panels)
-- 

-- Admin Jail - Teleport player to jail with timer
local AdminJailCoords = vector3(1641.6, 2571.0, 44.5) -- Default jail coords

RegisterNetEvent('lyxpanel:action:adminJail', function(targetId, duration, dryRun)
    local s = source
    if not HasPermission(s, 'canKick') then return end
    if _IsRateLimited(s, 'adminJail', _GetCooldownMs('adminJail', 1500)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    local targetName = GetPlayerName(targetId)
    if not targetName then return end

    duration = _AsInt(duration, 300)
    local maxMinutes = _GetLimitNumber('maxJailMinutes', 240)
    duration = math.max(10, math.min(duration, maxMinutes * 60))

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'ADMIN_JAIL', GetId(targetId, 'license'), targetName,
            { duration = duration, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] AdminJail simulado (no ejecutado)')
        return
    end

    -- Teleport to jail
    _TryGuardSafe(targetId, { 'movement', 'teleport' }, _GetGuardSafeMs('movement', 5000))
    TriggerClientEvent('lyxpanel:teleport', targetId, AdminJailCoords.x, AdminJailCoords.y, AdminJailCoords.z)

    -- Start jail timer
    TriggerClientEvent('lyxpanel:startJail', targetId, duration)
    TriggerClientEvent('lyxpanel:notify', targetId, 'error',
        'Has sido enviado a Admin Jail por ' .. math.floor(duration / 60) .. ' minutos')

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'ADMIN_JAIL', GetId(targetId, 'license'), targetName,
        { duration = duration })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador enviado a Admin Jail')
end)

-- Clear Ped - Reset player skin to default
RegisterNetEvent('lyxpanel:action:clearPed', function(targetId, dryRun)
    local s = source
    if not HasPermission(s, 'canSetModel') then return end
    if _IsRateLimited(s, 'clearPed', _GetCooldownMs('clearPed', 1500)) then return end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 or not GetPlayerName(targetId) then return end

    local targetName = GetPlayerName(targetId)
    if not targetName then return end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_PED', GetId(targetId, 'license'), targetName, { dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] ClearPed simulado (no ejecutado)')
        return
    end

    -- Reset skin to default male ped
    TriggerClientEvent('lyxpanel:resetPed', targetId)

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_PED', GetId(targetId, 'license'), targetName, {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Skin reseteada')
end)

-- Revive All - Revive all players on server
RegisterNetEvent('lyxpanel:action:reviveAll', function(dryRun)
    local s = source
    if not HasPermission(s, 'canRevive') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'reviveAll', _GetCooldownMs('reviveAll', 10000)) then return end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'REVIVE_ALL', '', '', { dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] ReviveAll simulado (no ejecutado)')
        return
    end

    local players = ESX.GetPlayers()
    local count = 0

    for _, playerId in ipairs(players) do
        TriggerClientEvent('esx_ambulancejob:revive', playerId)
        count = count + 1
    end

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'REVIVE_ALL', '', '', { count = count })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Revividos ' .. count .. ' jugadores')
end)

-- Give Money All - Give money to all players
RegisterNetEvent('lyxpanel:action:giveMoneyAll', function(amount, accountType, dryRun)
    local s = source
    if not HasPermission(s, 'canGiveMoney') then return end
    if not ESX then return end
    if _IsRateLimited(s, 'giveMoneyAll', _GetCooldownMs('giveMoneyAll', 15000)) then return end

    amount = _AsInt(amount, 0)
    local moneyMax = _GetLimitNumber('moneyMax', 10000000)
    if amount <= 0 or amount > moneyMax then
        TriggerClientEvent('lyxpanel:notify', s, 'error', ('Monto invalido (1-%d)'):format(moneyMax))
        return
    end

    accountType = tostring(accountType or 'money')
    if not _IsValidAccount(accountType) then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Cuenta invalida')
        return
    end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_MONEY_ALL', '', '',
            { amount = amount, account = accountType, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] GiveMoneyAll simulado (no ejecutado)')
        return
    end

    local players = ESX.GetPlayers()
    local count = 0

    for _, playerId in ipairs(players) do
        local xPlayer = ESX.GetPlayerFromId(playerId)
        if xPlayer then
            if accountType == 'money' then
                xPlayer.addMoney(amount)
            else
                xPlayer.addAccountMoney(accountType, amount)
            end
            count = count + 1
        end
    end

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_MONEY_ALL', '', '', { amount = amount, count = count })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Dados $' .. amount .. ' a ' .. count .. ' jugadores')
end)

-- Clear Area - Delete all vehicles/peds in radius
RegisterNetEvent('lyxpanel:action:clearArea', function(radius, dryRun)
    local s = source
    if not HasPermission(s, 'canDeleteNearby') then return end
    if _IsRateLimited(s, 'clearArea', _GetCooldownMs('clearArea', 3000)) then return end

    radius = _AsInt(radius, 100)
    radius = math.max(10, math.min(radius, 500))

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_AREA', '', '', { radius = radius, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] ClearArea simulado (no ejecutado)')
        return
    end

    TriggerClientEvent('lyxpanel:clearArea', s, radius)

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'CLEAR_AREA', '', '', { radius = radius })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Area limpiada (radio: ' .. radius .. 'm)')
end)

-- Global Announcement
RegisterNetEvent('lyxpanel:action:announcement', function(message, dryRun)
    local s = source
    if not HasPermission(s, 'canAnnounce') then return end
    if _IsRateLimited(s, 'announcement', _GetCooldownMs('announcement', 1500)) then return end

    local msgMax = _GetLimitNumber('maxAnnouncementLength', 250)
    message = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(message or '', msgMax)) or tostring(message or '')
    message = message:match('^%s*(.-)%s*$') or message
    message = message:sub(1, msgMax)
    if message == '' then return end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'ANNOUNCEMENT', '', '', { message = message, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] Announcement simulado (no ejecutado)')
        return
    end

    -- Send to all players
    TriggerClientEvent('chat:addMessage', -1, {
        template =
        '<div style="padding: 10px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); border-radius: 8px; margin: 5px 0;"><b>ANUNCIO</b><br>{0}</div>',
        args = { message }
    })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'ANNOUNCEMENT', '', '', { message = message })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Anuncio enviado')
end)

-- Wipe Player Data - Delete all player data (DANGEROUS)
RegisterNetEvent('lyxpanel:action:wipePlayer', function(targetId, confirmText, reason, dryRun)
    local s = source
    if not HasPermission(s, 'canWipePlayer') then return end

    local cdMs = _GetCooldownMs('wipePlayer', 10000)
    local dangerCfg = Config and Config.Permissions and Config.Permissions.dangerousActions or nil
    if dangerCfg and tonumber(dangerCfg.cooldown) then
        cdMs = math.max(cdMs, math.floor(tonumber(dangerCfg.cooldown)) * 1000)
    end
    if _IsRateLimited(s, 'wipePlayer', cdMs) then return end

    local expected = (dangerCfg and tostring(dangerCfg.confirmationText)) or 'CONFIRMO'
    confirmText = tostring(confirmText or ''):gsub('%s+', ''):upper()
    if confirmText ~= tostring(expected):gsub('%s+', ''):upper() then
        TriggerClientEvent('lyxpanel:notify', s, 'error',
            ('Confirmacion invalida (debe ser: %s)'):format(expected))
        return
    end

    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return end

    local targetName = GetPlayerName(targetId)
    if not targetName then return end

    local identifier = GetId(targetId, 'license')
    if not identifier or identifier == 'unknown' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Identifier invalido')
        return
    end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    reason = (LyxPanelLib and LyxPanelLib.Sanitize and LyxPanelLib.Sanitize(reason or '', reasonMax)) or tostring(reason or '')
    reason = reason:match('^%s*(.-)%s*$') or reason
    if reason == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Motivo obligatorio')
        return
    end

    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'WIPE_PLAYER', identifier, targetName,
            { reason = reason, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] Wipe simulado (no ejecutado)')
        return
    end

    -- Confirm action is intentional
    MySQL.update('DELETE FROM users WHERE identifier = ?', { identifier })

    DropPlayer(targetId, 'Tus datos han sido borrados por un administrador')

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'WIPE_PLAYER', identifier, targetName, { reason = reason })
    TriggerClientEvent('lyxpanel:notify', s, 'warning', 'Datos del jugador eliminados')
end)

-- Legacy duplicated block removed to keep a single authoritative implementation
-- for all admin actions in this file.




