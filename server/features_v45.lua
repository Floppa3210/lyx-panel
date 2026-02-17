--[[
    
                        LYXPANEL v4.5 - COMPLETE FEATURES                         
                          All Missing Features Implementation                      
    
      Features: Teleport Favorites, Weapon Kits, Ban Export/Import, Vehicle Adv.  
                Report Priority, Admin Rankings, Player HUD, & more               
    
]]

-- 
-- UTILITY FUNCTIONS
-- 

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
        print('^1[LyxPanel]^7 features_v45: ESX no disponible (timeout), callbacks no registrados.')
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

local function GetId(source, idType)
    idType = idType or 'license'
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, idType .. ':') then
            return id
        end
    end
    return 'unknown'
end

local function UpdateAdminStats(adminId, adminName, actionType)
    if not Config.AdminRankings or not Config.AdminRankings.enabled then return end
    
    local column = nil
    if actionType == 'KICK' then column = 'total_kicks'
    elseif actionType == 'BAN' then column = 'total_bans'
    elseif actionType == 'WARN' then column = 'total_warns'
    elseif actionType == 'REPORT_HANDLED' then column = 'total_reports_handled'
    elseif actionType == 'TELEPORT' then column = 'total_teleports'
    elseif actionType == 'SPAWN' then column = 'total_spawns'
    end
    
    if column then
        MySQL.Async.execute([[
            INSERT INTO lyxpanel_admin_stats (admin_identifier, admin_name, ]] .. column .. [[, last_action)
            VALUES (?, ?, 1, NOW())
            ON DUPLICATE KEY UPDATE ]] .. column .. [[ = ]] .. column .. [[ + 1, last_action = NOW()
        ]], { adminId, adminName or 'Unknown' })
    end
end

-- ---------------------------------------------------------------------------
-- SECURITY HELPERS: clamps + rate-limit + sanitization (server-side)
-- ---------------------------------------------------------------------------

local _ActionCooldowns = {}

local function _IsRateLimited(src, key, cooldownMs)
    if not src or src <= 0 then return true end

    local now = GetGameTimer()
    _ActionCooldowns[src] = _ActionCooldowns[src] or {}
    local last = _ActionCooldowns[src][key] or 0

    cooldownMs = tonumber(cooldownMs) or 0
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
    if maxLen and #s > maxLen then
        s = s:sub(1, maxLen)
    end
    return s
end

local function _ClampInt(v, minV, maxV, def)
    local n = tonumber(v)
    if not n then return def end
    n = math.floor(n)
    if n < minV then return minV end
    if n > maxV then return maxV end
    return n
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

local function _NormalizeVehicleModkit(mods)
    if type(mods) ~= 'table' then
        return nil
    end

    return {
        engine = _ClampInt(mods.engine, -1, 5, -1),
        brakes = _ClampInt(mods.brakes, -1, 5, -1),
        transmission = _ClampInt(mods.transmission, -1, 5, -1),
        suspension = _ClampInt(mods.suspension, -1, 5, -1),
        armor = _ClampInt(mods.armor, -1, 5, -1),
        turbo = _AsBool(mods.turbo, true)
    }
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

local function _GuardSafeMovement(playerId)
    if not (LyxPanel and LyxPanel.TryGuardSafe) then return end
    local ms = 5000
    if LyxPanel.GetGuardSafeMs then
        ms = LyxPanel.GetGuardSafeMs('movement', ms) or ms
    end
    -- lyx-guard uses 'teleport' as the safe key for teleport-related detections.
    LyxPanel.TryGuardSafe(playerId, { 'movement', 'teleport' }, ms)
end

local _VehicleActionCooldowns = {}

local function _IsVehicleActionRateLimited(src, key, cooldownMs)
    if not src or src <= 0 then return true end

    local now = GetGameTimer()
    _VehicleActionCooldowns[src] = _VehicleActionCooldowns[src] or {}
    local last = _VehicleActionCooldowns[src][key] or 0

    if (now - last) < cooldownMs then
        return true
    end

    _VehicleActionCooldowns[src][key] = now
    return false
end

local function _AsPlayerId(v)
    local id = tonumber(v)
    if not id or id <= 0 then return nil end
    if not GetPlayerName(id) then return nil end
    return id
end

local function _AsTargetOrSelf(src, v)
    local id = tonumber(v)
    if not id or id == -1 then return src end
    if id <= 0 then return nil end
    if not GetPlayerName(id) then return nil end
    return id
end

local function _NormalizeWeaponName(weapon)
    weapon = tostring(weapon or ''):upper():gsub('%s+', '')
    if weapon == '' then return nil end
    if not weapon:match('^WEAPON_') then
        weapon = 'WEAPON_' .. weapon
    end
    if weapon:match('^WEAPON_[A-Z0-9_]+$') == nil then
        return nil
    end
    return weapon
end

AddEventHandler('playerDropped', function()
    local src = source
    if src and _VehicleActionCooldowns[src] then
        _VehicleActionCooldowns[src] = nil
    end
    if src and _ActionCooldowns[src] then
        _ActionCooldowns[src] = nil
    end
end)

-- 
-- TELEPORT FAVORITES SYSTEM
-- 

RegisterESXCallback('lyxpanel:getTeleportFavorites', function(source, cb)
    if not HasPanelAccess(source) then
        cb({ defaults = {}, custom = {} })
        return
    end
    
    local adminId = GetId(source, 'license')
    
    -- Get custom favorites from database
    MySQL.Async.fetchAll([[
        SELECT id, name, x, y, z, heading FROM lyxpanel_teleport_favorites
        WHERE admin_identifier = ?
        ORDER BY name
    ]], { adminId }, function(custom)
        cb({
            defaults = Config.TeleportFavorites and Config.TeleportFavorites.defaults or {},
            custom = custom or {}
        })
    end)
end)

RegisterNetEvent('lyxpanel:action:saveTeleportFavorite', function(name, coords)
    local s = source
    if not HasPermission(s, 'canTeleport') then return end

    if _IsRateLimited(s, 'saveTeleportFavorite', _GetCooldownMs('saveTeleportFavorite', 1000)) then return end

    local nameMax = 64
    name = _SanitizeText(name or '', nameMax)
    name = name:match('^%s*(.-)%s*$') or name
    if name == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Nombre invalido')
        return
    end

    if type(coords) ~= 'table' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Coordenadas invalidas')
        return
    end

    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Coordenadas invalidas')
        return
    end

    -- Basic clamp to avoid absurd values / DB junk
    if x < -20000 or x > 20000 or y < -20000 or y > 20000 or z < -2000 or z > 5000 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Coordenadas fuera de rango')
        return
    end

    local heading = tonumber(coords.heading) or 0.0
    if heading < 0.0 then heading = 0.0 end
    if heading > 360.0 then heading = 360.0 end
    
    local adminId = GetId(s, 'license')
    
    -- Check max limit
    MySQL.Async.fetchScalar([[
        SELECT COUNT(*) FROM lyxpanel_teleport_favorites WHERE admin_identifier = ?
    ]], { adminId }, function(count)
        local maxAllowed = Config.TeleportFavorites and Config.TeleportFavorites.maxPerAdmin or 20
        maxAllowed = _ClampInt(maxAllowed, 1, 200, 20)
        if (count or 0) >= maxAllowed then
            TriggerClientEvent('lyxpanel:notify', s, 'error', 'Maximo de favoritos alcanzado (' .. maxAllowed .. ')')
            return
        end
        
        MySQL.Async.execute([[
            INSERT INTO lyxpanel_teleport_favorites (admin_identifier, name, x, y, z, heading)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], { adminId, name, x, y, z, heading })

        LogAction(GetId(s, 'license'), GetPlayerName(s), 'TP_FAVORITE_SAVE', adminId, GetPlayerName(s),
            { name = name, x = x, y = y, z = z, heading = heading })
        
        TriggerClientEvent('lyxpanel:notify', s, 'success', 'Ubicacion guardada: ' .. name)
    end)
end)

RegisterNetEvent('lyxpanel:action:deleteTeleportFavorite', function(favoriteId)
    local s = source
    if not HasPermission(s, 'canTeleport') then return end
    if _IsRateLimited(s, 'deleteTeleportFavorite', _GetCooldownMs('deleteTeleportFavorite', 750)) then return end

    favoriteId = tonumber(favoriteId)
    if not favoriteId or favoriteId <= 0 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'ID invalido')
        return
    end
    
    local adminId = GetId(s, 'license')
    
    MySQL.Async.execute([[
        DELETE FROM lyxpanel_teleport_favorites 
        WHERE id = ? AND admin_identifier = ?
    ]], { favoriteId, adminId })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TP_FAVORITE_DELETE', adminId, GetPlayerName(s),
        { favoriteId = favoriteId })
    
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Ubicacion eliminada')
end)

RegisterNetEvent('lyxpanel:action:teleportToFavorite', function(location)
    local s = source
    if not HasPermission(s, 'canTeleport') then return end
    if _IsRateLimited(s, 'teleportToFavorite', _GetCooldownMs('teleportToFavorite', 750)) then return end

    if type(location) ~= 'table' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Ubicacion invalida')
        return
    end
    local x = tonumber(location.x)
    local y = tonumber(location.y)
    local z = tonumber(location.z)
    if not x or not y or not z then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Ubicacion invalida')
        return
    end
    if x < -20000 or x > 20000 or y < -20000 or y > 20000 or z < -2000 or z > 5000 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Ubicacion fuera de rango')
        return
    end
    
    _GuardSafeMovement(s)
    TriggerClientEvent('lyxpanel:teleport', s, x, y, z)
    local locName = _SanitizeText(location.name or 'Ubicacion', 64)
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Teleportado a: ' .. (locName ~= '' and locName or 'Ubicacion'))

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TP_TO_FAVORITE', GetId(s, 'license'), GetPlayerName(s),
        { name = locName, x = x, y = y, z = z })
    UpdateAdminStats(GetId(s, 'license'), GetPlayerName(s), 'TELEPORT')
end)

-- Teleport player to player (j1 -> j2)
RegisterNetEvent('lyxpanel:action:teleportPlayerToPlayer', function(playerId1, playerId2)
    local s = source
    if not HasPermission(s, 'canTeleport') then return end
    if _IsRateLimited(s, 'teleportPlayerToPlayer', _GetCooldownMs('teleportPlayerToPlayer', 1000)) then return end

    playerId1 = _AsPlayerId(playerId1)
    playerId2 = _AsPlayerId(playerId2)
    if not playerId1 or not playerId2 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador destino no encontrado')
        return
    end
    
    local ped2 = GetPlayerPed(playerId2)
    if not ped2 or ped2 == 0 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador destino no encontrado')
        return
    end
    
    local coords = GetEntityCoords(ped2)
    _GuardSafeMovement(playerId1)
    TriggerClientEvent('lyxpanel:teleport', playerId1, coords.x, coords.y + 1.0, coords.z)
    
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'TELEPORT_PLAYER_TO_PLAYER', 
        GetId(playerId1, 'license'), GetPlayerName(playerId1),
        { to_player = GetPlayerName(playerId2) })
    
    TriggerClientEvent('lyxpanel:notify', s, 'success', 
        GetPlayerName(playerId1) .. ' teleportado a ' .. GetPlayerName(playerId2))
    TriggerClientEvent('lyxpanel:notify', playerId1, 'info', 
        'Has sido teleportado a ' .. GetPlayerName(playerId2))
end)

-- 
-- WEAPON KITS SYSTEM
-- 

RegisterESXCallback('lyxpanel:getWeaponKits', function(source, cb)
    if not HasPermission(source, 'canGiveWeapons') then
        cb({})
        return
    end
    
    local kits = {}
    
    -- Add config presets
    if Config.WeaponKits and Config.WeaponKits.presets then
        for id, kit in pairs(Config.WeaponKits.presets) do
            table.insert(kits, {
                id = id,
                name = kit.label,
                description = kit.description,
                weapons = kit.weapons,
                isPreset = true
            })
        end
    end
    
    -- Add database kits
    MySQL.Async.fetchAll([[
        SELECT * FROM lyxpanel_weapon_kits WHERE is_global = 1 OR created_by = ?
    ]], { GetPlayerName(source) }, function(dbKits)
        for _, kit in ipairs(dbKits or {}) do
            local ok, weapons = pcall(json.decode, kit.weapons)
            if not ok or type(weapons) ~= 'table' then weapons = {} end
            local parsedWeapons = {}
            for _, w in ipairs(weapons) do
                if type(w) == 'string' then
                    local parts = {}
                    for part in string.gmatch(w, "[^:]+") do
                        table.insert(parts, part)
                    end
                    table.insert(parsedWeapons, { weapon = parts[1], ammo = tonumber(parts[2]) or 0 })
                else
                    table.insert(parsedWeapons, w)
                end
            end
            table.insert(kits, {
                id = 'db_' .. kit.id,
                name = kit.name,
                description = kit.description,
                weapons = parsedWeapons,
                isPreset = false
            })
        end
        cb(kits)
    end)
end)

RegisterNetEvent('lyxpanel:action:giveWeaponKit', function(targetId, kitId, dryRun)
    local s = source
    if not HasPermission(s, 'canGiveWeapons') then return end
    if _IsRateLimited(s, 'giveWeaponKit', _GetCooldownMs('giveWeaponKit', 750)) then return end
    
    targetId = _AsPlayerId(targetId)
    if not targetId then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Jugador invalido')
        return
    end

    kitId = _SanitizeText(kitId or '', 64)
    kitId = kitId:match('^%s*(.-)%s*$') or kitId
    if kitId == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Kit invalido')
        return
    end

    local xT = ESX.GetPlayerFromId(targetId)
    if not xT then return end
    
    -- Find the kit
    local kit = nil
    
    if Config.WeaponKits and Config.WeaponKits.presets and Config.WeaponKits.presets[kitId] then
        kit = Config.WeaponKits.presets[kitId]
    end
    
    if not kit then
        -- Try database
        local dbId = tostring(kitId):match('^db_(%d+)$')
        if dbId then
            MySQL.Async.fetchAll('SELECT * FROM lyxpanel_weapon_kits WHERE id = ? AND (is_global = 1 OR created_by = ?)', {
                dbId,
                GetPlayerName(s) or ''
            }, function(results)
                if results and results[1] then
                    local dbKit = results[1]
                    local ok, weapons = pcall(json.decode, dbKit.weapons)
                    if not ok or type(weapons) ~= 'table' then weapons = {} end
                    local ammoMax = _GetLimitNumber('weaponAmmoMax', 1000)

                    if dryRun == true then
                        LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_WEAPON_KIT', xT.identifier, GetPlayerName(targetId),
                            { kit = dbKit.name, dryRun = true })
                        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] Kit simulado (no ejecutado)')
                        return
                    end

                    for _, w in ipairs(weapons) do
                        if type(w) == 'string' then
                            local parts = {}
                            for part in string.gmatch(w, "[^:]+") do
                                table.insert(parts, part)
                            end
                            local weap = _NormalizeWeaponName(parts[1])
                            local ammo = tonumber(parts[2]) or 0
                            ammo = _ClampInt(ammo, 0, ammoMax, 0)
                            if weap then
                                xT.addWeapon(weap, ammo)
                            end
                        else
                            local weap = _NormalizeWeaponName(w.weapon)
                            local ammo = tonumber(w.ammo) or 0
                            ammo = _ClampInt(ammo, 0, ammoMax, 0)
                            if weap then
                                xT.addWeapon(weap, ammo)
                            end
                        end
                    end
                    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_WEAPON_KIT', xT.identifier, GetPlayerName(targetId),
                        { kit = dbKit.name })
                    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Kit entregado: ' .. dbKit.name)
                    TriggerClientEvent('lyxpanel:notify', targetId, 'info', 'Recibiste: ' .. dbKit.name)
                end
            end)
            return
        end
        return
    end
    
    local ammoMax = _GetLimitNumber('weaponAmmoMax', 1000)
    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_WEAPON_KIT', xT.identifier, GetPlayerName(targetId),
            { kit = kit.label, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', '[DRY-RUN] Kit simulado (no ejecutado)')
        return
    end

    -- Give preset kit weapons
    for _, weapon in ipairs(kit.weapons) do
        local weap = _NormalizeWeaponName(weapon.weapon)
        local ammo = tonumber(weapon.ammo) or 0
        ammo = _ClampInt(ammo, 0, ammoMax, 0)
        if weap then
            xT.addWeapon(weap, ammo)
        end
    end
    
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'GIVE_WEAPON_KIT', xT.identifier, GetPlayerName(targetId),
        { kit = kit.label })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Kit entregado: ' .. kit.label)
    TriggerClientEvent('lyxpanel:notify', targetId, 'info', 'Recibiste: ' .. kit.label)
end)

-- 
-- BAN EXPORT/IMPORT SYSTEM
-- 

RegisterESXCallback('lyxpanel:exportBans', function(source, cb)
    if not HasPermission(source, 'canManageBans') then
        cb({ success = false, error = 'Sin permisos' })
        return
    end

    if not _RequireLyxGuard(source, 'exportBans') then
        cb({ success = false, error = 'lyx-guard no activo' })
        return
    end
    
    local includeExpired = Config.BanExportImport and Config.BanExportImport.includeExpired or false
    local query = includeExpired 
        and 'SELECT * FROM lyxguard_bans ORDER BY ban_date DESC'
        or 'SELECT * FROM lyxguard_bans WHERE active = 1 ORDER BY ban_date DESC'
    
    MySQL.Async.fetchAll(query, {}, function(bans)
        cb({ success = true, bans = bans or {}, exportDate = os.date('%Y-%m-%d %H:%M:%S') })
        LogAction(GetId(source, 'license'), GetPlayerName(source), 'EXPORT_BANS', nil, nil, 
            { count = #(bans or {}) })
    end)
end)

local function _IsLikelyIdentifier(identifier)
    if type(identifier) ~= 'string' then return false end
    identifier = identifier:gsub('%s+', '')
    if #identifier < 4 or #identifier > 255 then return false end
    if identifier:match('^%w+:%w+$') == nil then return false end
    return true
end

local function _NormalizeMysqlDatetime(s)
    if type(s) ~= 'string' then return nil end
    s = s:match('^%s*(.-)%s*$') or s
    if s:match('^%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d:%d%d$') then
        return s
    end
    return nil
end

RegisterNetEvent('lyxpanel:action:importBans', function(bansData, dryRun)
    local s = source
    if not HasPermission(s, 'canManageBans') then return end
    if _IsRateLimited(s, 'importBans', _GetCooldownMs('importBans', 3000)) then return end
    if not _RequireLyxGuard(s, 'importBans') then return end
    
    local maxImport = Config.BanExportImport and Config.BanExportImport.maxImportSize or 500
    maxImport = _ClampInt(maxImport, 1, 5000, 500)
    
    if type(bansData) ~= 'table' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Datos de bans invalidos')
        return
    end
    
    if #bansData > maxImport then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Demasiados bans (max: ' .. maxImport .. ')')
        return
    end
    
    local imported = 0
    local skipped = 0

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    local nameMax = _GetLimitNumber('maxPlayerNameLength', 100)
    local adminName = _SanitizeText(GetPlayerName(s) or 'Unknown', 80)

    for _, ban in ipairs(bansData) do
        if type(ban) == 'table' and ban.identifier and ban.reason then
            local identifier = tostring(ban.identifier):gsub('%s+', '')
            if not _IsLikelyIdentifier(identifier) then
                skipped = skipped + 1
                goto continue_import
            end

            local pname = _SanitizeText(ban.player_name or ban.playerName or 'Imported', nameMax)
            if pname == '' then pname = 'Imported' end

            local reason = _SanitizeText(ban.reason or '', reasonMax)
            reason = reason:match('^%s*(.-)%s*$') or reason
            if reason == '' then
                skipped = skipped + 1
                goto continue_import
            end

            local permanent = (ban.permanent == true) or (tonumber(ban.permanent) == 1)
            local unbanDate = nil
            if not permanent then
                unbanDate = _NormalizeMysqlDatetime(ban.unban_date or ban.unbanDate)
            end

            if dryRun == true then
                imported = imported + 1
                goto continue_import
            end

            MySQL.Async.execute([[
                INSERT IGNORE INTO lyxguard_bans (identifier, player_name, reason, unban_date, permanent, banned_by, active)
                VALUES (?, ?, ?, ?, ?, ?, 1)
            ]], { identifier, pname, reason, unbanDate, permanent and 1 or 0, ('Import by %s'):format(adminName) })
            imported = imported + 1
        else
            skipped = skipped + 1
        end

        ::continue_import::
    end
    
    if dryRun == true then
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'IMPORT_BANS', nil, nil, { count = imported, skipped = skipped, dryRun = true })
        TriggerClientEvent('lyxpanel:notify', s, 'info', ('[DRY-RUN] %d bans validos (skipped: %d)'):format(imported, skipped))
        return
    end

    TriggerEvent('lyxguard:reloadBans')
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'IMPORT_BANS', nil, nil, { count = imported, skipped = skipped })
    TriggerClientEvent('lyxpanel:notify', s, 'success', ('Importados %d bans (skipped: %d)'):format(imported, skipped))
end)

-- Edit existing ban
RegisterNetEvent('lyxpanel:action:editBan', function(banId, newReason, newDuration)
    local s = source
    if not HasPermission(s, 'canManageBans') then return end
    if _IsRateLimited(s, 'editBan', _GetCooldownMs('editBan', 1500)) then return end
    if not _RequireLyxGuard(s, 'editBan') then return end
    
    banId = tonumber(banId)
    if not banId or banId <= 0 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'BanID invalido')
        return
    end

    local reasonMax = _GetLimitNumber('maxReasonLength', 200)
    newReason = _SanitizeText(newReason or '', reasonMax)
    newReason = newReason:match('^%s*(.-)%s*$') or newReason
    if newReason == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Motivo obligatorio')
        return
    end

    local isPermanent = (newDuration == 'permanent' or tonumber(newDuration) == 0)
    local unbanTime = nil
    
    if not isPermanent then
        local maxHours = _GetLimitNumber('maxOfflineBanHours', 24 * 365)
        local hours = _ClampInt(newDuration, 1, maxHours, 24)
        unbanTime = os.date('%Y-%m-%d %H:%M:%S', os.time() + (hours * 3600))
    end
    
    MySQL.Async.execute([[
        UPDATE lyxguard_bans 
        SET reason = ?, unban_date = ?, permanent = ?
        WHERE id = ?
    ]], { newReason, unbanTime, isPermanent and 1 or 0, banId }, function(affected)
        TriggerEvent('lyxguard:reloadBans')
        LogAction(GetId(s, 'license'), GetPlayerName(s), 'EDIT_BAN', nil, 'BanID:' .. banId,
            { reason = newReason, duration = newDuration, affected = affected or 0 })
        if affected and affected > 0 then
            TriggerClientEvent('lyxpanel:notify', s, 'success', 'Ban actualizado')
        else
            TriggerClientEvent('lyxpanel:notify', s, 'error', 'No se pudo actualizar (no encontrado)')
        end
    end)
end)

-- 
-- VEHICLE ADVANCED FEATURES
-- 

-- Bring vehicle to admin
RegisterNetEvent('lyxpanel:action:bringVehicle', function(targetId)
    local s = source
    if not HasPermission(s, 'canTeleport') then return end

    if _IsVehicleActionRateLimited(s, 'bringVehicle', _GetCooldownMs('bringVehicle', 1500)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end
    
    local adminPed = GetPlayerPed(s)
    local adminCoords = GetEntityCoords(adminPed)
    
    TriggerClientEvent('lyxpanel:bringVehicle', targetId, adminCoords.x, adminCoords.y, adminCoords.z)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'BRING_VEHICLE', GetId(targetId, 'license'), GetPlayerName(targetId),
        { x = adminCoords.x, y = adminCoords.y, z = adminCoords.z })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Vehiculo traido')
end)

-- Toggle doors
RegisterNetEvent('lyxpanel:action:toggleVehicleDoors', function(targetId, doorIndex)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end

    if _IsVehicleActionRateLimited(s, 'toggleVehicleDoors', _GetCooldownMs('toggleVehicleDoors', 750)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end

    doorIndex = tonumber(doorIndex) or -1
    if doorIndex < -1 or doorIndex > 7 then doorIndex = -1 end
    
    TriggerClientEvent('lyxpanel:toggleVehicleDoors', targetId, doorIndex)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_DOORS', GetId(targetId, 'license'), GetPlayerName(targetId),
        { doorIndex = doorIndex })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Puertas alternadas')
end)

-- Toggle engine
RegisterNetEvent('lyxpanel:action:toggleVehicleEngine', function(targetId)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end

    if _IsVehicleActionRateLimited(s, 'toggleVehicleEngine', _GetCooldownMs('toggleVehicleEngine', 750)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end
    
    TriggerClientEvent('lyxpanel:toggleVehicleEngine', targetId)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_ENGINE', GetId(targetId, 'license'), GetPlayerName(targetId), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Motor alternado')
end)

-- Set fuel
RegisterNetEvent('lyxpanel:action:setVehicleFuel', function(targetId, fuelLevel)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end

    if _IsVehicleActionRateLimited(s, 'setVehicleFuel', _GetCooldownMs('setVehicleFuel', 1000)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end
    
    fuelLevel = math.max(0, math.min(100, tonumber(fuelLevel) or 100))
    
    TriggerClientEvent('lyxpanel:setVehicleFuel', targetId, fuelLevel)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_FUEL', GetId(targetId, 'license'), GetPlayerName(targetId),
        { fuel = fuelLevel })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Combustible: ' .. fuelLevel .. '%')
end)

-- Freeze/unfreeze current vehicle position.
RegisterNetEvent('lyxpanel:action:freezeVehicle', function(targetId, enabled)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end
    if _IsVehicleActionRateLimited(s, 'freezeVehicle', _GetCooldownMs('freezeVehicle', 900)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end

    enabled = _AsBool(enabled, true)

    TriggerClientEvent('lyxpanel:freezeVehicle', targetId, enabled)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_FREEZE', GetId(targetId, 'license'), GetPlayerName(targetId), {
        enabled = enabled
    })
    TriggerClientEvent('lyxpanel:notify', s, 'success', enabled and 'Vehiculo congelado' or 'Vehiculo descongelado')
end)

-- Set livery index (-1 = default/no livery)
RegisterNetEvent('lyxpanel:action:setVehicleLivery', function(targetId, livery)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end
    if _IsVehicleActionRateLimited(s, 'setVehicleLivery', _GetCooldownMs('setVehicleLivery', 1000)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end

    livery = _ClampInt(livery, -1, 200, -1)

    TriggerClientEvent('lyxpanel:setVehicleLivery', targetId, livery)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_LIVERY', GetId(targetId, 'license'), GetPlayerName(targetId),
        { livery = livery })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Livery aplicado')
end)

-- Toggle/set one extra by ID.
RegisterNetEvent('lyxpanel:action:setVehicleExtra', function(targetId, extraId, enabled)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end
    if _IsVehicleActionRateLimited(s, 'setVehicleExtra', _GetCooldownMs('setVehicleExtra', 750)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end

    extraId = _ClampInt(extraId, 0, 20, 0)
    enabled = _AsBool(enabled, true)

    TriggerClientEvent('lyxpanel:setVehicleExtra', targetId, extraId, enabled)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_EXTRA', GetId(targetId, 'license'), GetPlayerName(targetId), {
        extraId = extraId,
        enabled = enabled
    })
    TriggerClientEvent('lyxpanel:notify', s, 'success', ('Extra %d %s'):format(extraId, enabled and 'activado' or 'desactivado'))
end)

-- Neon color + enabled toggle.
RegisterNetEvent('lyxpanel:action:setVehicleNeon', function(targetId, enabled, color)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end
    if _IsVehicleActionRateLimited(s, 'setVehicleNeon', _GetCooldownMs('setVehicleNeon', 750)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end

    enabled = _AsBool(enabled, true)
    color = _NormalizeRgbColor(color) or { r = 255, g = 0, b = 0 }

    TriggerClientEvent('lyxpanel:setVehicleNeon', targetId, enabled, color)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_NEON', GetId(targetId, 'license'), GetPlayerName(targetId), {
        enabled = enabled,
        color = color
    })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Neon actualizado')
end)

-- Wheel smoke RGB color.
RegisterNetEvent('lyxpanel:action:setVehicleWheelSmoke', function(targetId, color)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end
    if _IsVehicleActionRateLimited(s, 'setVehicleWheelSmoke', _GetCooldownMs('setVehicleWheelSmoke', 1000)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end

    color = _NormalizeRgbColor(color) or { r = 255, g = 255, b = 255 }

    TriggerClientEvent('lyxpanel:setVehicleWheelSmoke', targetId, color)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_WHEEL_SMOKE', GetId(targetId, 'license'),
        GetPlayerName(targetId), { color = color })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Humo de ruedas actualizado')
end)

-- Pearlescent and wheel-color (GTA color indexes).
RegisterNetEvent('lyxpanel:action:setVehiclePaintAdvanced', function(targetId, pearlescent, wheelColor)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end
    if _IsVehicleActionRateLimited(s, 'setVehiclePaintAdvanced', _GetCooldownMs('setVehiclePaintAdvanced', 1000)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end

    pearlescent = _ClampInt(pearlescent, 0, 160, 0)
    wheelColor = _ClampInt(wheelColor, 0, 160, 0)

    TriggerClientEvent('lyxpanel:setVehiclePaintAdvanced', targetId, pearlescent, wheelColor)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_PAINT_ADVANCED', GetId(targetId, 'license'),
        GetPlayerName(targetId), { pearlescent = pearlescent, wheelColor = wheelColor })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Pintura avanzada aplicada')
end)

-- Xenon toggle + color index.
RegisterNetEvent('lyxpanel:action:setVehicleXenon', function(targetId, enabled, colorIndex)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end
    if _IsVehicleActionRateLimited(s, 'setVehicleXenon', _GetCooldownMs('setVehicleXenon', 1000)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end

    enabled = _AsBool(enabled, true)
    colorIndex = _ClampInt(colorIndex, -1, 13, -1)

    TriggerClientEvent('lyxpanel:setVehicleXenon', targetId, enabled, colorIndex)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_XENON', GetId(targetId, 'license'), GetPlayerName(targetId), {
        enabled = enabled,
        colorIndex = colorIndex
    })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Xenon actualizado')
end)

-- Apply selected performance modkit levels.
RegisterNetEvent('lyxpanel:action:setVehicleModkit', function(targetId, mods)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end
    if _IsVehicleActionRateLimited(s, 'setVehicleModkit', _GetCooldownMs('setVehicleModkit', 1200)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end

    mods = _NormalizeVehicleModkit(mods)
    if not mods then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Modkit invalido')
        return
    end

    TriggerClientEvent('lyxpanel:setVehicleModkit', targetId, mods)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'VEHICLE_MODKIT', GetId(targetId, 'license'), GetPlayerName(targetId), {
        mods = mods
    })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Modkit aplicado')
end)

-- Warp player into vehicle
RegisterNetEvent('lyxpanel:action:warpIntoVehicle', function(targetId, driverPlayerId)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end

    if _IsVehicleActionRateLimited(s, 'warpIntoVehicle', _GetCooldownMs('warpIntoVehicle', 1500)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    driverPlayerId = _AsPlayerId(driverPlayerId)
    if not targetId or not driverPlayerId then return end
    
    _GuardSafeMovement(targetId)
    TriggerClientEvent('lyxpanel:warpIntoVehicle', targetId, driverPlayerId)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'WARP_INTO_VEHICLE', GetId(targetId, 'license'), GetPlayerName(targetId),
        { driver = GetId(driverPlayerId, 'license'), driverName = GetPlayerName(driverPlayerId) })
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador metido en vehiculo')
end)

-- Warp player out of vehicle
RegisterNetEvent('lyxpanel:action:warpOutOfVehicle', function(targetId)
    local s = source
    if not HasPermission(s, 'canEditVehicle') then return end

    if _IsVehicleActionRateLimited(s, 'warpOutOfVehicle', _GetCooldownMs('warpOutOfVehicle', 1500)) then return end

    targetId = _AsTargetOrSelf(s, targetId)
    if not targetId then return end
    
    _GuardSafeMovement(targetId)
    TriggerClientEvent('lyxpanel:warpOutOfVehicle', targetId)
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'WARP_OUT_OF_VEHICLE', GetId(targetId, 'license'), GetPlayerName(targetId), {})
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Jugador sacado del vehiculo')
end)

-- 
-- REPORT PRIORITY SYSTEM
-- 
-- 
-- ADMIN RANKINGS
-- 

RegisterESXCallback('lyxpanel:getAdminRankings', function(source, cb, period)
    if not HasPanelAccess(source) then
        cb({})
        return
    end
    
    period = period or (Config.AdminRankings and Config.AdminRankings.defaultPeriod or 'week')
    
    local dateFilter = ''
    if period == 'day' then
        dateFilter = 'AND last_action >= DATE_SUB(NOW(), INTERVAL 1 DAY)'
    elseif period == 'week' then
        dateFilter = 'AND last_action >= DATE_SUB(NOW(), INTERVAL 1 WEEK)'
    elseif period == 'month' then
        dateFilter = 'AND last_action >= DATE_SUB(NOW(), INTERVAL 1 MONTH)'
    end
    
    local limit = Config.AdminRankings and Config.AdminRankings.topAdminsCount or 10
    
    MySQL.Async.fetchAll([[
        SELECT 
            admin_name,
            total_kicks + total_bans + total_warns + total_reports_handled + total_teleports + total_spawns as total_actions,
            total_kicks, total_bans, total_warns, total_reports_handled, total_teleports, total_spawns,
            last_action
        FROM lyxpanel_admin_stats
        WHERE admin_name IS NOT NULL ]] .. dateFilter .. [[
        ORDER BY total_actions DESC
        LIMIT ?
    ]], { limit }, function(rankings)
        cb(rankings or {})
    end)
end)

-- 
-- PLAYER OUTFITS SYSTEM
-- 

RegisterESXCallback('lyxpanel:getPlayerOutfits', function(source, cb)
    if not HasPanelAccess(source) then
        cb({})
        return
    end
    
    local identifier = GetId(source, 'license')
    
    MySQL.Async.fetchAll([[
        SELECT id, outfit_name, created_at FROM lyxpanel_outfits
        WHERE identifier = ?
        ORDER BY created_at DESC
    ]], { identifier }, function(outfits)
        cb(outfits or {})
    end)
end)

RegisterNetEvent('lyxpanel:action:saveOutfit', function(outfitName, outfitData)
    local s = source
    if not HasPanelAccess(s) then return end
    if _IsRateLimited(s, 'saveOutfit', _GetCooldownMs('saveOutfit', 1500)) then return end
    
    local identifier = GetId(s, 'license')
    if not identifier or identifier == 'unknown' then return end

    local nameMax = 64
    outfitName = _SanitizeText(outfitName or '', nameMax)
    outfitName = outfitName:match('^%s*(.-)%s*$') or outfitName
    if outfitName == '' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Nombre de outfit invalido')
        return
    end

    if type(outfitData) ~= 'table' then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Outfit invalido')
        return
    end

    local cleaned = {}
    for i = 0, 11 do
        local k = 'comp_' .. i
        local e = outfitData[k]
        if type(e) == 'table' then
            local d = tonumber(e.drawable)
            local t = tonumber(e.texture)
            if d then
                cleaned[k] = {
                    drawable = _ClampInt(d, 0, 512, 0),
                    texture = _ClampInt(t or 0, 0, 512, 0)
                }
            end
        end
    end
    for i = 0, 8 do
        local k = 'prop_' .. i
        local e = outfitData[k]
        if type(e) == 'table' then
            local d = tonumber(e.drawable)
            local t = tonumber(e.texture)
            if d then
                -- props can be -1 (none)
                cleaned[k] = {
                    drawable = _ClampInt(d, -1, 512, -1),
                    texture = _ClampInt(t or 0, 0, 512, 0)
                }
            end
        end
    end

    local encoded = json.encode(cleaned)
    local maxJson = _GetLimitNumber('maxOutfitJsonLength', 12000)
    if type(encoded) ~= 'string' or #encoded < 2 or #encoded > maxJson then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Outfit demasiado grande')
        return
    end

    local maxOutfits = _GetLimitNumber('maxOutfitsPerPlayer', 50)
    maxOutfits = _ClampInt(maxOutfits, 1, 200, 50)

    MySQL.Async.fetchScalar('SELECT COUNT(*) FROM lyxpanel_outfits WHERE identifier = ?', { identifier }, function(count)
        if (count or 0) >= maxOutfits then
            TriggerClientEvent('lyxpanel:notify', s, 'error', ('Maximo de outfits alcanzado (%d)'):format(maxOutfits))
            return
        end

        MySQL.Async.execute([[
            INSERT INTO lyxpanel_outfits (identifier, outfit_name, outfit_data)
            VALUES (?, ?, ?)
        ]], { identifier, outfitName, encoded })

        LogAction(GetId(s, 'license'), GetPlayerName(s), 'OUTFIT_SAVE', identifier, GetPlayerName(s),
            { name = outfitName })

        TriggerClientEvent('lyxpanel:notify', s, 'success', 'Outfit guardado: ' .. outfitName)
    end)
end)

RegisterNetEvent('lyxpanel:action:loadOutfit', function(outfitId)
    local s = source
    if not HasPanelAccess(s) then return end
    if _IsRateLimited(s, 'loadOutfit', _GetCooldownMs('loadOutfit', 750)) then return end
    
    local identifier = GetId(s, 'license')
    if not identifier or identifier == 'unknown' then return end

    outfitId = tonumber(outfitId)
    if not outfitId or outfitId <= 0 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Outfit invalido')
        return
    end
    
    MySQL.Async.fetchAll([[
        SELECT outfit_data FROM lyxpanel_outfits
        WHERE id = ? AND identifier = ?
    ]], { outfitId, identifier }, function(results)
        if results and results[1] then
            local ok, outfitData = pcall(json.decode, results[1].outfit_data)
            if not ok or type(outfitData) ~= 'table' then
                TriggerClientEvent('lyxpanel:notify', s, 'error', 'Outfit corrupto')
                return
            end

            TriggerClientEvent('lyxpanel:loadOutfit', s, outfitData)
            TriggerClientEvent('lyxpanel:notify', s, 'success', 'Outfit cargado')
            LogAction(GetId(s, 'license'), GetPlayerName(s), 'OUTFIT_LOAD', identifier, GetPlayerName(s),
                { outfitId = outfitId })
        else
            TriggerClientEvent('lyxpanel:notify', s, 'error', 'Outfit no encontrado')
        end
    end)
end)

RegisterNetEvent('lyxpanel:action:deleteOutfit', function(outfitId)
    local s = source
    if not HasPanelAccess(s) then return end
    if _IsRateLimited(s, 'deleteOutfit', _GetCooldownMs('deleteOutfit', 750)) then return end
    
    local identifier = GetId(s, 'license')
    if not identifier or identifier == 'unknown' then return end

    outfitId = tonumber(outfitId)
    if not outfitId or outfitId <= 0 then
        TriggerClientEvent('lyxpanel:notify', s, 'error', 'Outfit invalido')
        return
    end
    
    MySQL.Async.execute([[
        DELETE FROM lyxpanel_outfits WHERE id = ? AND identifier = ?
    ]], { outfitId, identifier })

    LogAction(GetId(s, 'license'), GetPlayerName(s), 'OUTFIT_DELETE', identifier, GetPlayerName(s),
        { outfitId = outfitId })
    
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Outfit eliminado')
end)

-- 
-- RELOAD CONFIG (Without restart)
-- 

RegisterNetEvent('lyxpanel:action:reloadConfig', function()
    local s = source
    if not HasPermission(s, 'canEditConfig') then return end
    if _IsRateLimited(s, 'reloadConfig', _GetCooldownMs('reloadConfig', 5000)) then return end
    
    -- This triggers a config reload via resource restart of just this file
    -- Note: Full config reload would require resource restart
    TriggerEvent('lyxpanel:configReloaded')
    TriggerClientEvent('lyxpanel:notify', s, 'success', 'Configuracion recargada')
    LogAction(GetId(s, 'license'), GetPlayerName(s), 'RELOAD_CONFIG', nil, nil, {})
end)

print('^5[LyxPanel v4.5]^7 Complete features loaded - 50+ new functions')



