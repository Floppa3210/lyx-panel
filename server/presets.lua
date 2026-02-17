--[[
    LyxPanel - Presets & Pro Tools

    Features:
    - Self presets (health/armor/movement/admin tools) save/load
    - Vehicle build presets (tuning/colors/extras) save/apply
    - Vehicle favorites + spawn history

    Security:
    - Server-side permission checks
    - Rate-limits
    - Strict input validation (names + JSON payload)
]]

local ESX = ESX

CreateThread(function()
    local resolved = ESX
    if LyxPanel and LyxPanel.WaitForESX then
        resolved = LyxPanel.WaitForESX(15000)
    end

    ESX = resolved or ESX or _G.ESX
    if ESX then
        _G.ESX = _G.ESX or ESX
    else
        print('^1[LyxPanel]^7 presets: ESX no disponible (timeout).')
    end
end)

local _Cooldowns = {} -- [src][key] = lastMs

local function _NowMs()
    return GetGameTimer()
end

local function _IsRateLimited(src, key, cooldownMs)
    if not src or src <= 0 then return true end
    cooldownMs = tonumber(cooldownMs) or 0
    local now = _NowMs()
    _Cooldowns[src] = _Cooldowns[src] or {}
    local last = _Cooldowns[src][key] or 0
    if (now - last) < cooldownMs then
        return true
    end
    _Cooldowns[src][key] = now
    return false
end

local function _GetId(source, idType)
    idType = idType or 'license'
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, idType .. ':') then
            return id
        end
    end
    return 'unknown'
end

local function _HasPerm(src, perm)
    if type(HasPermission) == 'function' then
        local ok, allowed = pcall(function()
            return HasPermission(src, perm)
        end)
        if ok then return allowed == true end
    end
    return IsPlayerAceAllowed(src, 'lyxpanel.admin') or IsPlayerAceAllowed(src, 'lyxpanel.access')
end

local function _HasPanel(src)
    if type(HasPanelAccess) == 'function' then
        local ok, allowed = pcall(function()
            return HasPanelAccess(src)
        end)
        if ok then
            if type(allowed) == 'table' then
                return allowed[1] == true
            end
            return allowed == true
        end
    end
    return IsPlayerAceAllowed(src, 'lyxpanel.admin') or IsPlayerAceAllowed(src, 'lyxpanel.access')
end

local function _SanitizeText(s, maxLen, pattern)
    if LyxPanelLib and LyxPanelLib.Sanitize then
        s = LyxPanelLib.Sanitize(s, maxLen)
    else
        s = tostring(s or ''):gsub('[%c]', ''):gsub('[\r\n\t]', ' ')
        if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    end
    s = s:match('^%s*(.-)%s*$') or s
    if s == '' then return nil end
    if pattern and not s:match(pattern) then
        return nil
    end
    return s
end

local function _ClampInt(v, minV, maxV, def)
    local n = tonumber(v)
    if not n then return def end
    n = math.floor(n)
    if minV ~= nil and n < minV then n = minV end
    if maxV ~= nil and n > maxV then n = maxV end
    return n
end

local function _ClampNum(v, minV, maxV, def)
    local n = tonumber(v)
    if not n then return def end
    if minV ~= nil and n < minV then n = minV end
    if maxV ~= nil and n > maxV then n = maxV end
    return n
end

local function _NormalizeVehicleModel(model)
    if type(model) ~= 'string' then return nil end
    model = model:match('^%s*(.-)%s*$') or model
    model = model:gsub('%s+', ''):lower()
    if model == '' then return nil end
    if #model > 32 then model = model:sub(1, 32) end
    if not model:match('^[%w_]+$') then return nil end
    return model
end

local function _NormalizePresetName(name)
    name = _SanitizeText(name, 64)
    if not name then return nil end
    if not name:match('^[%w%s%-%_%.]+$') then
        return nil
    end
    return name
end

local function _NormalizeRgbColor(value)
    if type(value) ~= 'table' then return nil end
    local r = _ClampInt(value.r, 0, 255, nil)
    local g = _ClampInt(value.g, 0, 255, nil)
    local b = _ClampInt(value.b, 0, 255, nil)
    if r == nil or g == nil or b == nil then return nil end
    return { r = r, g = g, b = b }
end

local function _NormalizeBool(v, def)
    if type(v) == 'boolean' then return v end
    if type(v) == 'number' then return v ~= 0 end
    if type(v) == 'string' then
        local s = v:lower():gsub('%s+', '')
        if s == 'true' or s == '1' or s == 'yes' or s == 'on' then return true end
        if s == 'false' or s == '0' or s == 'no' or s == 'off' then return false end
    end
    return def
end

local function _LogAdmin(src, action, targetId, targetName, details)
    if type(LogAction) == 'function' then
        pcall(function()
            LogAction(_GetId(src, 'license'), GetPlayerName(src) or 'Unknown', action, targetId, targetName, details or {})
        end)
        return
    end
end

local function _ValidateSelfPresetData(data)
    if type(data) ~= 'table' then return nil end

    local out = {}
    out.health = _ClampInt(data.health, 0, 200, nil)
    out.armor = _ClampInt(data.armor, 0, 100, nil)
    out.noclip = _NormalizeBool(data.noclip, nil)
    out.noclipSpeed = _ClampNum(data.noclipSpeed, 0.1, 6.0, nil)

    local mode = type(data.godmodeMode) == 'string' and data.godmodeMode:lower() or nil
    local allowed = { off = true, full = true, pve = true, fire = true, fall = true }
    if mode and allowed[mode] then
        out.godmodeMode = mode
    end

    out.invisible = _NormalizeBool(data.invisible, nil)
    out.adminHud = _NormalizeBool(data.adminHud, nil)
    out.overlayNames = _NormalizeBool(data.overlayNames, nil)
    out.sprintMultiplier = _ClampNum(data.sprintMultiplier, 1.0, 2.5, nil)
    out.superJump = _NormalizeBool(data.superJump, nil)

    return out
end

local function _ValidateVehicleBuild(build)
    if type(build) ~= 'table' then return nil end

    local out = {}

    -- Colors can be either index (number) or RGB tables.
    if type(build.primary) == 'number' then
        out.primary = _ClampInt(build.primary, 0, 160, nil)
    else
        out.primary = _NormalizeRgbColor(build.primary)
    end

    if type(build.secondary) == 'number' then
        out.secondary = _ClampInt(build.secondary, 0, 160, nil)
    else
        out.secondary = _NormalizeRgbColor(build.secondary)
    end

    out.pearlescent = _ClampInt(build.pearlescent, 0, 160, nil)
    out.wheelColor = _ClampInt(build.wheelColor, 0, 160, nil)
    out.livery = _ClampInt(build.livery, -1, 200, nil)

    local plate = _SanitizeText(build.plate, 8, '^[A-Z0-9]+$')
    if plate then out.plate = plate end

    local neonColor = _NormalizeRgbColor(build.neonColor)
    local neonEnabled = _NormalizeBool(build.neonEnabled, nil)
    if neonEnabled ~= nil then
        out.neonEnabled = neonEnabled
    end
    if neonColor then out.neonColor = neonColor end

    local smokeColor = _NormalizeRgbColor(build.smokeColor)
    if smokeColor then out.smokeColor = smokeColor end

    local xenonEnabled = _NormalizeBool(build.xenonEnabled, nil)
    local xenonColor = _ClampInt(build.xenonColor, -1, 13, nil)
    if xenonEnabled ~= nil then out.xenonEnabled = xenonEnabled end
    if xenonColor ~= nil then out.xenonColor = xenonColor end

    -- Modkit (performance)
    if type(build.mods) == 'table' then
        out.mods = {
            engine = _ClampInt(build.mods.engine, -1, 5, -1),
            brakes = _ClampInt(build.mods.brakes, -1, 5, -1),
            transmission = _ClampInt(build.mods.transmission, -1, 5, -1),
            suspension = _ClampInt(build.mods.suspension, -1, 5, -1),
            armor = _ClampInt(build.mods.armor, -1, 5, -1),
            turbo = _NormalizeBool(build.mods.turbo, false)
        }
    end

    -- Extras: { [id] = true/false }
    if type(build.extras) == 'table' then
        local extras = {}
        local count = 0
        for k, v in pairs(build.extras) do
            local id = _ClampInt(k, 0, 20, nil)
            if id ~= nil then
                extras[tostring(id)] = _NormalizeBool(v, false) == true
                count = count + 1
                if count >= 32 then break end
            end
        end
        out.extras = extras
    end

    return out
end

-- ---------------------------------------------------------------------------
-- ESX CALLBACKS (NUI)
-- ---------------------------------------------------------------------------

ESX.RegisterServerCallback('lyxpanel:getSelfPresets', function(source, cb)
    if not _HasPanel(source) then return cb({}) end
    if not _HasPerm(source, 'canManagePresets') then return cb({}) end

    local adminId = _GetId(source, 'license')
    MySQL.query(
        'SELECT id, name, updated_at, created_at FROM lyxpanel_self_presets WHERE admin_identifier = ? ORDER BY updated_at DESC',
        { adminId },
        function(rows)
            cb(rows or {})
        end
    )
end)

ESX.RegisterServerCallback('lyxpanel:getVehicleBuilds', function(source, cb)
    if not _HasPanel(source) then return cb({}) end
    if not _HasPerm(source, 'canManagePresets') then return cb({}) end

    local adminId = _GetId(source, 'license')
    MySQL.query(
        'SELECT id, name, updated_at, created_at FROM lyxpanel_vehicle_builds WHERE admin_identifier = ? ORDER BY updated_at DESC',
        { adminId },
        function(rows)
            cb(rows or {})
        end
    )
end)

ESX.RegisterServerCallback('lyxpanel:getVehicleFavorites', function(source, cb)
    if not _HasPanel(source) then return cb({}) end
    if not _HasPerm(source, 'canManagePresets') then return cb({}) end

    local adminId = _GetId(source, 'license')
    MySQL.query(
        'SELECT id, model, label, created_at FROM lyxpanel_vehicle_favorites WHERE admin_identifier = ? ORDER BY created_at DESC',
        { adminId },
        function(rows)
            cb(rows or {})
        end
    )
end)

ESX.RegisterServerCallback('lyxpanel:getVehicleSpawnHistory', function(source, cb, limit)
    if not _HasPanel(source) then return cb({}) end
    if not _HasPerm(source, 'canManagePresets') then return cb({}) end

    local max = _ClampInt(limit, 1, 200, 50)
    local adminId = _GetId(source, 'license')
    MySQL.query(
        'SELECT id, model, label, target_identifier, target_name, created_at FROM lyxpanel_vehicle_spawn_history WHERE admin_identifier = ? ORDER BY created_at DESC LIMIT ?',
        { adminId, max },
        function(rows)
            cb(rows or {})
        end
    )
end)

-- ---------------------------------------------------------------------------
-- ACTIONS
-- ---------------------------------------------------------------------------

RegisterNetEvent('lyxpanel:action:saveSelfPreset', function(name, data)
    local src = source
    if not _HasPerm(src, 'canManagePresets') then return end
    if _IsRateLimited(src, 'saveSelfPreset', 1500) then return end

    local presetName = _NormalizePresetName(name)
    if not presetName then
        TriggerClientEvent('lyxpanel:notify', src, 'error', 'Nombre de preset invalido')
        return
    end

    local preset = _ValidateSelfPresetData(data)
    if not preset then
        TriggerClientEvent('lyxpanel:notify', src, 'error', 'Preset invalido')
        return
    end

    local adminId = _GetId(src, 'license')
    local payload = json.encode(preset)

    MySQL.insert([[
        INSERT INTO lyxpanel_self_presets (admin_identifier, name, data)
        VALUES (?, ?, CAST(? AS JSON))
        ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = CURRENT_TIMESTAMP
    ]], { adminId, presetName, payload }, function()
        _LogAdmin(src, 'SELF_PRESET_SAVE', adminId, GetPlayerName(src) or 'admin', { name = presetName })
        TriggerClientEvent('lyxpanel:notify', src, 'success', 'Preset guardado')
    end)
end)

RegisterNetEvent('lyxpanel:action:deleteSelfPreset', function(presetId)
    local src = source
    if not _HasPerm(src, 'canManagePresets') then return end
    if _IsRateLimited(src, 'deleteSelfPreset', 750) then return end

    presetId = _ClampInt(presetId, 1, 2147483647, nil)
    if not presetId then return end

    local adminId = _GetId(src, 'license')
    MySQL.update('DELETE FROM lyxpanel_self_presets WHERE id = ? AND admin_identifier = ?', { presetId, adminId }, function(aff)
        _LogAdmin(src, 'SELF_PRESET_DELETE', adminId, GetPlayerName(src) or 'admin', { presetId = presetId, affected = aff or 0 })
        TriggerClientEvent('lyxpanel:notify', src, 'success', 'Preset eliminado')
    end)
end)

RegisterNetEvent('lyxpanel:action:loadSelfPreset', function(presetId)
    local src = source
    if not _HasPerm(src, 'canManagePresets') then return end
    if _IsRateLimited(src, 'loadSelfPreset', 750) then return end

    presetId = _ClampInt(presetId, 1, 2147483647, nil)
    if not presetId then return end

    local adminId = _GetId(src, 'license')
    MySQL.query('SELECT data, name FROM lyxpanel_self_presets WHERE id = ? AND admin_identifier = ? LIMIT 1',
        { presetId, adminId }, function(rows)
            local row = rows and rows[1]
            if not row or not row.data then
                TriggerClientEvent('lyxpanel:notify', src, 'error', 'Preset no encontrado')
                return
            end

            local decoded = nil
            pcall(function() decoded = json.decode(row.data) end)
            if type(decoded) ~= 'table' then
                TriggerClientEvent('lyxpanel:notify', src, 'error', 'Preset corrupto')
                return
            end

            _LogAdmin(src, 'SELF_PRESET_LOAD', adminId, GetPlayerName(src) or 'admin', { presetId = presetId, name = row.name })
            TriggerClientEvent('lyxpanel:selfPresetLoaded', src, decoded)
            TriggerClientEvent('lyxpanel:notify', src, 'success', ('Preset aplicado: %s'):format(tostring(row.name or '')))
        end)
end)

RegisterNetEvent('lyxpanel:action:saveVehicleBuild', function(name, build)
    local src = source
    if not _HasPerm(src, 'canManagePresets') then return end
    if not _HasPerm(src, 'canEditVehicle') then return end
    if _IsRateLimited(src, 'saveVehicleBuild', 1500) then return end

    local presetName = _NormalizePresetName(name)
    if not presetName then
        TriggerClientEvent('lyxpanel:notify', src, 'error', 'Nombre de build invalido')
        return
    end

    local normalized = _ValidateVehicleBuild(build)
    if not normalized then
        TriggerClientEvent('lyxpanel:notify', src, 'error', 'Build invalido')
        return
    end

    local adminId = _GetId(src, 'license')
    local payload = json.encode(normalized)

    MySQL.insert([[
        INSERT INTO lyxpanel_vehicle_builds (admin_identifier, name, build)
        VALUES (?, ?, CAST(? AS JSON))
        ON DUPLICATE KEY UPDATE build = VALUES(build), updated_at = CURRENT_TIMESTAMP
    ]], { adminId, presetName, payload }, function()
        _LogAdmin(src, 'VEHICLE_BUILD_SAVE', adminId, GetPlayerName(src) or 'admin', { name = presetName })
        TriggerClientEvent('lyxpanel:notify', src, 'success', 'Build guardado')
    end)
end)

RegisterNetEvent('lyxpanel:action:deleteVehicleBuild', function(buildId)
    local src = source
    if not _HasPerm(src, 'canManagePresets') then return end
    if _IsRateLimited(src, 'deleteVehicleBuild', 750) then return end

    buildId = _ClampInt(buildId, 1, 2147483647, nil)
    if not buildId then return end

    local adminId = _GetId(src, 'license')
    MySQL.update('DELETE FROM lyxpanel_vehicle_builds WHERE id = ? AND admin_identifier = ?', { buildId, adminId }, function(aff)
        _LogAdmin(src, 'VEHICLE_BUILD_DELETE', adminId, GetPlayerName(src) or 'admin', { buildId = buildId, affected = aff or 0 })
        TriggerClientEvent('lyxpanel:notify', src, 'success', 'Build eliminado')
    end)
end)

RegisterNetEvent('lyxpanel:action:applyVehicleBuild', function(buildId)
    local src = source
    if not _HasPerm(src, 'canEditVehicle') then return end
    if _IsRateLimited(src, 'applyVehicleBuild', 500) then return end

    buildId = _ClampInt(buildId, 1, 2147483647, nil)
    if not buildId then return end

    local adminId = _GetId(src, 'license')
    MySQL.query('SELECT build, name FROM lyxpanel_vehicle_builds WHERE id = ? AND admin_identifier = ? LIMIT 1',
        { buildId, adminId }, function(rows)
            local row = rows and rows[1]
            if not row or not row.build then
                TriggerClientEvent('lyxpanel:notify', src, 'error', 'Build no encontrado')
                return
            end

            local decoded = nil
            pcall(function() decoded = json.decode(row.build) end)
            if type(decoded) ~= 'table' then
                TriggerClientEvent('lyxpanel:notify', src, 'error', 'Build corrupto')
                return
            end

            _LogAdmin(src, 'VEHICLE_BUILD_APPLY', adminId, GetPlayerName(src) or 'admin', { buildId = buildId, name = row.name })
            TriggerClientEvent('lyxpanel:vehicle:applyBuild', src, decoded)
            TriggerClientEvent('lyxpanel:notify', src, 'success', ('Build aplicado: %s'):format(tostring(row.name or '')))
        end)
end)

RegisterNetEvent('lyxpanel:action:addVehicleFavorite', function(model, label)
    local src = source
    if not _HasPerm(src, 'canManagePresets') then return end
    if _IsRateLimited(src, 'addVehicleFavorite', 400) then return end

    local m = _NormalizeVehicleModel(model)
    if not m then
        TriggerClientEvent('lyxpanel:notify', src, 'error', 'Modelo invalido')
        return
    end

    local l = _SanitizeText(label, 100)

    local adminId = _GetId(src, 'license')
    MySQL.insert([[
        INSERT INTO lyxpanel_vehicle_favorites (admin_identifier, model, label)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE label = VALUES(label)
    ]], { adminId, m, l }, function()
        _LogAdmin(src, 'VEHICLE_FAVORITE_ADD', adminId, GetPlayerName(src) or 'admin', { model = m })
        TriggerClientEvent('lyxpanel:notify', src, 'success', 'Agregado a favoritos')
    end)
end)

RegisterNetEvent('lyxpanel:action:removeVehicleFavorite', function(favoriteId)
    local src = source
    if not _HasPerm(src, 'canManagePresets') then return end
    if _IsRateLimited(src, 'removeVehicleFavorite', 400) then return end

    favoriteId = _ClampInt(favoriteId, 1, 2147483647, nil)
    if not favoriteId then return end

    local adminId = _GetId(src, 'license')
    MySQL.update('DELETE FROM lyxpanel_vehicle_favorites WHERE id = ? AND admin_identifier = ?', { favoriteId, adminId }, function(aff)
        _LogAdmin(src, 'VEHICLE_FAVORITE_REMOVE', adminId, GetPlayerName(src) or 'admin', { favoriteId = favoriteId, affected = aff or 0 })
        TriggerClientEvent('lyxpanel:notify', src, 'success', 'Favorito eliminado')
    end)
end)

-- v4.5: server-side helper used by actions.lua to track vehicle spawn history (best-effort)
exports('TrackVehicleSpawnHistory', function(adminSource, model, label, targetIdentifier, targetName)
    if not adminSource or adminSource <= 0 or not GetPlayerName(adminSource) then return end
    if not MySQL or not MySQL.insert then return end

    local adminId = _GetId(adminSource, 'license')
    local m = _NormalizeVehicleModel(model) or tostring(model or ''):sub(1, 32)
    local l = _SanitizeText(label, 100)
    local tid = type(targetIdentifier) == 'string' and targetIdentifier:sub(1, 255) or nil
    local tn = _SanitizeText(targetName, 100)

    pcall(function()
        MySQL.insert(
            'INSERT INTO lyxpanel_vehicle_spawn_history (admin_identifier, model, label, target_identifier, target_name) VALUES (?,?,?,?,?)',
            { adminId, m, l, tid, tn }
        )
    end)
end)

print('^2[LyxPanel]^7 presets module loaded')

