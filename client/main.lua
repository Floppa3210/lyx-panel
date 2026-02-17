--[[
    LyxPanel v3.0 - Client Main
    50+ Funciones de administracin
]]

-- ESX es proporcionado por @es_extended/imports.lua
local isOpen = false
local adminPerms = {}
local uiConfig = {}
local panelSecurity = {
    enabled = false,
    token = nil,
    tokenTtlMs = 0,
    nonceCounter = 0,
}
local _randSeeded = false

-- Admin state
local noclipActive = false
local godmodeActive = false
local invisibleActive = false
local spectateTarget = nil
local spectatePos = nil
local noclipSpeed = 1.0
local speedboostActive = false
local nitroActive = false
local vehicleGodmodeActive = false

-- Forward declarations
local OpenPanel

local function _SetPanelSecurity(sec)
    if type(sec) ~= 'table' then
        panelSecurity.enabled = false
        panelSecurity.token = nil
        panelSecurity.tokenTtlMs = 0
        panelSecurity.nonceCounter = 0
        return
    end

    panelSecurity.enabled = sec.enabled == true and type(sec.token) == 'string' and sec.token ~= ''
    panelSecurity.token = panelSecurity.enabled and sec.token or nil
    panelSecurity.tokenTtlMs = tonumber(sec.tokenTtlMs) or 0
    panelSecurity.nonceCounter = 0
end

local function _GenerateSecurityEnvelope(eventName)
    if not _randSeeded then
        local seed = GetGameTimer() + math.floor((GetFrameTime() or 0.0) * 1000000) + GetPlayerServerId(PlayerId())
        math.randomseed(seed)
        for _ = 1, 8 do math.random() end
        _randSeeded = true
    end

    if panelSecurity.enabled ~= true or type(panelSecurity.token) ~= 'string' or panelSecurity.token == '' then
        return nil
    end

    panelSecurity.nonceCounter = (tonumber(panelSecurity.nonceCounter) or 0) + 1
    local now = GetGameTimer()
    local nonce = ('%d-%d-%d'):format(math.random(100000, 999999), now, panelSecurity.nonceCounter)
    local correlationId = ('lp-%d-%d-%d'):format(GetPlayerServerId(PlayerId()), now, panelSecurity.nonceCounter)

    return {
        __lyxsec = {
            token = panelSecurity.token,
            nonce = nonce,
            correlation_id = correlationId,
            ts = os.time() * 1000,
            event = tostring(eventName or '')
        }
    }
end

local function SendSecureServerEvent(eventName, ...)
    local args = { ... }
    local env = _GenerateSecurityEnvelope(eventName)
    if env then
        args[#args + 1] = env
    end
    TriggerServerEvent(eventName, table.unpack(args))
end

-- Shared secure trigger for other client modules (client_extended/features/staff/spectate).
function LyxPanelSecureTrigger(eventName, ...)
    if type(eventName) ~= 'string' or eventName == '' then
        return
    end
    SendSecureServerEvent(eventName, ...)
end

-- ...............................................................................
-- ABRIR/CERRAR PANEL
-- ...............................................................................

OpenPanel = function()
    print('[LyxPanel] Intentando abrir panel...')
    if isOpen then
        print('[LyxPanel] Panel ya est marcado como abierto. Ignorando.')
        return
    end

    print('[LyxPanel] Solicitando acceso al servidor...')
    ESX.TriggerServerCallback('lyxpanel:checkAccess', function(data)
        print('[LyxPanel] Respuesta de acceso recibida:', json.encode(data))
        if data and data.access then
            adminPerms = data.permissions or {}
            _SetPanelSecurity(data.security)
            print('[LyxPanel] Acceso concedido. Solicitando config...')
            ESX.TriggerServerCallback('lyxpanel:getConfig', function(cfg)
                print('[LyxPanel] Config recibida. Abriendo NUI...')
                uiConfig = cfg or {}
                SetNuiFocus(true, true)
                SendNUIMessage({
                    action = 'open',
                    permissions = adminPerms,
                    group = data.group,
                    config = uiConfig,
                    integrations = data.integrations or {}
                })
                isOpen = true
                SendSecureServerEvent('lyxpanel:panelSession', true)
                RefreshData()
                SendSecureServerEvent('lyxpanel:requestStaffSync')
            end)
        else
            _SetPanelSecurity(nil)
            print('[LyxPanel] Acceso denegado.')
            SetNotificationTextEntry('STRING')
            AddTextComponentString('~r~Sin acceso al panel')
            DrawNotification(true, true)
        end
    end)
end

RegisterCommand('lyxpanel_debug_reset', function()
    isOpen = false
    SetNuiFocus(false, false)
    _SetPanelSecurity(nil)
    print('[LyxPanel] Estado reseteado forzosamente.')
end, false)

-- ... (cdigo intermedio) ...



-- ...............................................................................
-- COMANDO Y KEYBIND
-- ...............................................................................

RegisterCommand('panel', function()
    if isOpen then
        SetNuiFocus(false, false)
        isOpen = false
        SendSecureServerEvent('lyxpanel:panelSession', false)
        _SetPanelSecurity(nil)
        SendNUIMessage({ action = 'close' })
    else
        OpenPanel()
    end
end, false)

RegisterKeyMapping('panel', 'Abrir Panel Admin LyxPanel', 'keyboard', 'F6')

-- Event handler for other scripts
AddEventHandler('lyxpanel:open', OpenPanel)

RegisterNUICallback('close', function(data, cb)
    SetNuiFocus(false, false)
    isOpen = false
    SendSecureServerEvent('lyxpanel:panelSession', false)
    _SetPanelSecurity(nil)
    cb({})
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if isOpen then
        SendSecureServerEvent('lyxpanel:panelSession', false)
    end
    _SetPanelSecurity(nil)
end)

-- ...............................................................................
-- CALLBACKS NUI
-- ...............................................................................

function RefreshData()
    ESX.TriggerServerCallback('lyxpanel:getStats', function(stats)
        SendNUIMessage({ action = 'updateStats', stats = stats })
    end)
    ESX.TriggerServerCallback('lyxpanel:getPlayers', function(players)
        SendNUIMessage({ action = 'updatePlayers', players = players })
    end)
end

RegisterNUICallback('refresh', function(data, cb)
    RefreshData()
    cb({})
end)

RegisterNUICallback('getPlayerDetails', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getPlayerDetails', function(details)
        cb(details or {})
    end, data.playerId)
end)

RegisterNUICallback('getDetections', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getDetections', function(r) cb(r or {}) end, data.limit or 100)
end)

RegisterNUICallback('getBans', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getBans', function(r) cb(r or {}) end)
end)

RegisterNUICallback('getReports', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getReports', function(r) cb(r or {}) end)
end)

RegisterNUICallback('getReportMessages', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getReportMessages', function(r) cb(r or {}) end, data.reportId)
end)

RegisterNUICallback('getLogs', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getLogs', function(r) cb(r or {}) end, data.limit or 100)
end)

RegisterNUICallback('getDependencyStatus', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getDependencyStatus', function(r)
        cb(r or { success = false, error = 'no_data' })
    end)
end)

-- Audit logs (filters + pagination)
RegisterNUICallback('queryLogs', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:queryLogs', function(r)
        cb(r or { success = false, error = 'no_data' })
    end, data)
end)

RegisterNUICallback('exportLogs', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:exportLogs', function(r)
        cb(r or { success = false, error = 'no_data' })
    end, data)
end)

-- Permission editor (masters)
RegisterNUICallback('getPermissionEditorData', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getPermissionEditorData', function(r)
        cb(r or { success = false, error = 'no_data' })
    end)
end)

RegisterNUICallback('getRolePermissions', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getRolePermissions', function(r)
        cb(r or { success = false, error = 'no_data' })
    end, data.role)
end)

RegisterNUICallback('setRolePermission', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:setRolePermission', function(r)
        cb(r or { success = false, error = 'no_data' })
    end, data.role, data.permission, data.value)
end)

RegisterNUICallback('resetRoleOverride', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:resetRoleOverride', function(r)
        cb(r or { success = false, error = 'no_data' })
    end, data.role)
end)

RegisterNUICallback('getIndividualPermissions', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getIndividualPermissions', function(r)
        cb(r or { success = false, error = 'no_data' })
    end, data.identifier)
end)

RegisterNUICallback('setIndividualPermission', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:setIndividualPermission', function(r)
        cb(r or { success = false, error = 'no_data' })
    end, data.identifier, data.permission, data.value)
end)

RegisterNUICallback('resetIndividualPermission', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:resetIndividualPermission', function(r)
        cb(r or { success = false, error = 'no_data' })
    end, data.identifier, data.permission)
end)

-- Panel access list (masters)
RegisterNUICallback('listAccessEntries', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:listAccessEntries', function(r)
        cb(r or { success = false, error = 'no_data' })
    end)
end)

RegisterNUICallback('setAccessEntry', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:setAccessEntry', function(r)
        cb(r or { success = false, error = 'no_data' })
    end, data.identifier, data.group, data.note)
end)

RegisterNUICallback('removeAccessEntry', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:removeAccessEntry', function(r)
        cb(r or { success = false, error = 'no_data' })
    end, data.identifier)
end)

RegisterNUICallback('getTickets', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getTickets', function(r)
        cb(r or { success = false, error = 'no_data', rows = {}, total = 0, offset = 0, limit = 0 })
    end, data or {})
end)

RegisterNUICallback('getTransactions', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getTransactions', function(r) cb(r or {}) end, data.playerId)
end)

RegisterNUICallback('getJobs', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getJobs', function(r) cb(r or {}) end)
end)

RegisterNUICallback('getGarage', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getGarage', function(r) cb(r or {}) end, data.playerId)
end)

RegisterNUICallback('searchPlayers', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:searchPlayers', function(r)
        cb(r or {})
    end, data.query)
end)

-- ---------------------------------------------------------------------------
-- PRESETS / VEHICLE PRO TOOLS (NUI -> server callbacks)
-- ---------------------------------------------------------------------------

RegisterNUICallback('getSelfPresets', function(_data, cb)
    ESX.TriggerServerCallback('lyxpanel:getSelfPresets', function(r) cb(r or {}) end)
end)

RegisterNUICallback('getVehicleBuilds', function(_data, cb)
    ESX.TriggerServerCallback('lyxpanel:getVehicleBuilds', function(r) cb(r or {}) end)
end)

RegisterNUICallback('getVehicleFavorites', function(_data, cb)
    ESX.TriggerServerCallback('lyxpanel:getVehicleFavorites', function(r) cb(r or {}) end)
end)

RegisterNUICallback('getVehicleSpawnHistory', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getVehicleSpawnHistory', function(r) cb(r or {}) end, data and data.limit or 50)
end)

-- Snapshot helpers (client-side; used by NUI to build preset/build payloads).
RegisterNUICallback('getSelfSnapshot', function(_data, cb)
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    local armor = GetPedArmour(ped)

    cb({
        ok = true,
        snapshot = {
            health = health,
            armor = armor,
            noclip = noclipActive == true,
            noclipSpeed = noclipSpeed,
            godmodeMode = godmodeActive == true and 'full' or 'off',
            invisible = invisibleActive == true,
            sprintMultiplier = speedboostActive == true and 1.49 or nil,
        }
    })
end)

RegisterNUICallback('getCurrentVehicleBuild', function(_data, cb)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        cb({ ok = false, error = 'no_vehicle' })
        return
    end

    local build = {}

    build.plate = GetVehicleNumberPlateText(veh)

    local primaryIndex, secondaryIndex = GetVehicleColours(veh)
    if GetIsVehiclePrimaryColourCustom(veh) then
        local r, g, b = GetVehicleCustomPrimaryColour(veh)
        build.primary = { r = r, g = g, b = b }
    else
        build.primary = primaryIndex
    end
    if GetIsVehicleSecondaryColourCustom(veh) then
        local r, g, b = GetVehicleCustomSecondaryColour(veh)
        build.secondary = { r = r, g = g, b = b }
    else
        build.secondary = secondaryIndex
    end

    local pearl, wheel = GetVehicleExtraColours(veh)
    build.pearlescent = pearl
    build.wheelColor = wheel

    build.livery = GetVehicleLivery(veh)

    local neonOn = false
    for i = 0, 3 do
        if IsVehicleNeonLightEnabled(veh, i) then
            neonOn = true
            break
        end
    end
    build.neonEnabled = neonOn
    do
        local r, g, b = GetVehicleNeonLightsColour(veh)
        build.neonColor = { r = r, g = g, b = b }
    end

    do
        local r, g, b = GetVehicleTyreSmokeColor(veh)
        build.smokeColor = { r = r, g = g, b = b }
    end

    build.xenonEnabled = IsToggleModOn(veh, 22) == true
    build.xenonColor = GetVehicleXenonLightsColour(veh)

    build.mods = {
        engine = GetVehicleMod(veh, 11),
        brakes = GetVehicleMod(veh, 12),
        transmission = GetVehicleMod(veh, 13),
        suspension = GetVehicleMod(veh, 15),
        armor = GetVehicleMod(veh, 16),
        turbo = IsToggleModOn(veh, 18) == true
    }

    local extras = {}
    for i = 0, 20 do
        if DoesExtraExist(veh, i) then
            extras[tostring(i)] = IsVehicleExtraTurnedOn(veh, i) == true
        end
    end
    build.extras = extras

    cb({ ok = true, build = build })
end)

-- ---------------------------------------------------------------------------
-- ELITE TOOLS (freecam/scan/cleanup/warps)
-- ---------------------------------------------------------------------------

local _WarpsCache = nil
local _FreecamProxyActive = false

local function _Distance(a, b)
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function _LoadWarps()
    local raw = GetResourceKvpString('lyxpanel_warps')
    if type(raw) ~= 'string' or raw == '' then
        return {}
    end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        return {}
    end
    return data
end

local function _SaveWarps(warps)
    local ok, payload = pcall(json.encode, warps or {})
    if ok and type(payload) == 'string' then
        SetResourceKvp('lyxpanel_warps', payload)
    end
end

local function _GetWarps()
    if type(_WarpsCache) ~= 'table' then
        _WarpsCache = _LoadWarps()
    end
    return _WarpsCache
end

local function _NormalizeWarpName(name)
    if type(name) ~= 'string' then
        name = tostring(name or '')
    end
    name = name:gsub('[%c]', ' ')
    name = name:gsub('%s+', ' ')
    name = name:match('^%s*(.-)%s*$') or ''
    if #name < 1 then return nil end
    if #name > 40 then
        name = name:sub(1, 40)
    end
    return name
end

local function _TryDeleteEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    if NetworkGetEntityIsNetworked(entity) then
        NetworkRequestControlOfEntity(entity)
        local timeoutAt = GetGameTimer() + 250
        while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeoutAt do
            Wait(0)
            NetworkRequestControlOfEntity(entity)
        end
    end

    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
    return not DoesEntityExist(entity)
end

RegisterNUICallback('toggleFreecam', function(data, cb)
    if not isOpen then
        cb({ success = false, error = 'panel_closed' })
        return
    end

    _FreecamProxyActive = not _FreecamProxyActive
    SendSecureServerEvent('lyxpanel:action:noclip')
    cb({ success = true, active = _FreecamProxyActive })
end)

RegisterNUICallback('scanArea', function(data, cb)
    if not isOpen then
        cb({ vehicles = 0, players = 0, peds = 0, error = 'panel_closed' })
        return
    end

    local radius = tonumber(data and data.radius) or 100.0
    if radius < 10.0 then radius = 10.0 end
    if radius > 500.0 then radius = 500.0 end

    local myPed = PlayerPedId()
    local center = GetEntityCoords(myPed)
    local vehicles = 0
    local players = 0
    local peds = 0

    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) and _Distance(GetEntityCoords(veh), center) <= radius then
            vehicles = vehicles + 1
        end
    end

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= myPed and DoesEntityExist(ped) and _Distance(GetEntityCoords(ped), center) <= radius then
            players = players + 1
        end
    end

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and _Distance(GetEntityCoords(ped), center) <= radius then
            peds = peds + 1
        end
    end

    cb({
        vehicles = vehicles,
        players = players,
        peds = peds
    })
end)

RegisterNUICallback('cleanupZone', function(data, cb)
    if not isOpen then
        cb({ vehicles = 0, peds = 0, objects = 0, error = 'panel_closed' })
        return
    end

    local radius = tonumber(data and data.radius) or 100.0
    if radius < 10.0 then radius = 10.0 end
    if radius > 500.0 then radius = 500.0 end

    local cleanVehicles = (data and data.vehicles) == true
    local cleanPeds = (data and data.peds) == true
    local cleanObjects = (data and data.objects) == true

    local myPed = PlayerPedId()
    local myVeh = GetVehiclePedIsIn(myPed, false)
    local center = GetEntityCoords(myPed)
    local removed = { vehicles = 0, peds = 0, objects = 0 }

    if cleanVehicles then
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if veh ~= myVeh and DoesEntityExist(veh) and _Distance(GetEntityCoords(veh), center) <= radius then
                if _TryDeleteEntity(veh) then
                    removed.vehicles = removed.vehicles + 1
                end
            end
        end
    end

    if cleanPeds then
        for _, ped in ipairs(GetGamePool('CPed')) do
            if ped ~= myPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) and _Distance(GetEntityCoords(ped), center) <= radius then
                if _TryDeleteEntity(ped) then
                    removed.peds = removed.peds + 1
                end
            end
        end
    end

    if cleanObjects then
        for _, obj in ipairs(GetGamePool('CObject')) do
            if DoesEntityExist(obj) and _Distance(GetEntityCoords(obj), center) <= radius then
                if _TryDeleteEntity(obj) then
                    removed.objects = removed.objects + 1
                end
            end
        end
    end

    cb(removed)
end)

RegisterNUICallback('spectateNearest', function(data, cb)
    if not isOpen then
        cb({ success = false, error = 'panel_closed' })
        return
    end

    local myPed = PlayerPedId()
    local center = GetEntityCoords(myPed)
    local nearestId = nil
    local nearestDist = 999999.0

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= myPed and DoesEntityExist(ped) then
            local dist = _Distance(GetEntityCoords(ped), center)
            if dist < nearestDist then
                nearestDist = dist
                nearestId = GetPlayerServerId(player)
            end
        end
    end

    if nearestId and nearestDist <= 300.0 then
        SendSecureServerEvent('lyxpanel:action:spectate', nearestId)
        cb({ success = true, distance = nearestDist, targetId = nearestId })
        return
    end

    cb({ success = false })
end)

RegisterNUICallback('getWarps', function(data, cb)
    if not isOpen then
        cb({})
        return
    end

    cb(_GetWarps())
end)

RegisterNUICallback('addWarp', function(data, cb)
    if not isOpen then
        cb({ success = false, error = 'panel_closed' })
        return
    end

    local name = _NormalizeWarpName(data and data.name or '')
    if not name then
        cb({ success = false, error = 'invalid_name' })
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local warps = _GetWarps()
    local replaced = false

    for i = 1, #warps do
        if tostring(warps[i].name or ''):lower() == name:lower() then
            warps[i] = { name = name, x = coords.x, y = coords.y, z = coords.z, heading = heading }
            replaced = true
            break
        end
    end

    if not replaced then
        warps[#warps + 1] = { name = name, x = coords.x, y = coords.y, z = coords.z, heading = heading }
    end

    _SaveWarps(warps)
    cb({ success = true })
end)

RegisterNUICallback('teleportToWarp', function(data, cb)
    if not isOpen then
        cb({ success = false, error = 'panel_closed' })
        return
    end

    local name = _NormalizeWarpName(data and data.name or '')
    if not name then
        cb({ success = false, error = 'invalid_name' })
        return
    end

    local warps = _GetWarps()
    for i = 1, #warps do
        local w = warps[i]
        if tostring(w.name or ''):lower() == name:lower() then
            local x = tonumber(w.x)
            local y = tonumber(w.y)
            local z = tonumber(w.z)
            local h = tonumber(w.heading) or 0.0
            if x and y and z then
                SetEntityCoordsNoOffset(PlayerPedId(), x, y, z, false, false, false)
                SetEntityHeading(PlayerPedId(), h)
                cb({ success = true })
                return
            end
            break
        end
    end

    cb({ success = false, error = 'not_found' })
end)

RegisterNUICallback('deleteWarp', function(data, cb)
    if not isOpen then
        cb({ success = false, error = 'panel_closed' })
        return
    end

    local name = _NormalizeWarpName(data and data.name or '')
    if not name then
        cb({ success = false, error = 'invalid_name' })
        return
    end

    local warps = _GetWarps()
    local idx = nil
    for i = 1, #warps do
        if tostring(warps[i].name or ''):lower() == name:lower() then
            idx = i
            break
        end
    end

    if not idx then
        cb({ success = false, error = 'not_found' })
        return
    end

    table.remove(warps, idx)
    _SaveWarps(warps)
    cb({ success = true })
end)

-- ...............................................................................
-- ACCIONES NUI
-- ...............................................................................

local AllowedPanelActions = {
    kick = true,
    ban = true,
    unban = true,
    warn = true,
    giveMoney = true,
    setMoney = true,
    removeMoney = true,
    transferMoney = true,
    giveWeapon = true,
    giveAmmo = true,
    removeWeapon = true,
    removeAllWeapons = true,
    giveItem = true,
    removeItem = true,
    clearInventory = true,
    spawnVehicle = true,
    quickSpawnWarpTune = true,
    deleteVehicle = true,
    repairVehicle = true,
    flipVehicle = true,
    boostVehicle = true,
    deleteNearby = true,
    deleteNearbyVehicles = true, -- alias
    cleanVehicle = true,
    setVehicleColor = true,
    setVehiclePlate = true,
    tuneVehicle = true,
    ghostVehicle = true,
    getVehicleInfo = true,
    teleportTo = true,
    bring = true,
    teleportCoords = true,
    teleportMarker = true,
    teleportBack = true,
    heal = true,
    revive = true,
    reviveRadius = true,
    setArmor = true,
    setHealth = true,
    freeze = true,
    spectate = true,
    kill = true,
    slap = true,
    ragdoll = true,
    jail = true,
    unjail = true,
    muteChat = true,
    muteVoice = true,
    unmute = true,
    setJob = true,
    noclip = true,
    godmode = true,
    invisible = true,
    speedboost = true,
    nitro = true,
    vehicleGodmode = true,
    announce = true,
    privateMessage = true,
    adminChat = true,
    addNote = true,
    setWeather = true,
    setTime = true,
    addWhitelist = true,
    removeWhitelist = true,
    assignReport = true,
    tpToReporter = true,
    closeReport = true,
    setReportPriority = true,
    clearLogs = true,
    clearAllDetections = true,
    changeModel = true,
    screenshot = true,
    screenshotBatch = true,
    troll_explode = true,
    troll_fire = true,
    troll_launch = true,
    troll_ragdoll = true,
    troll_drunk = true,
    troll_drug = true,
    troll_blackscreen = true,
    troll_scream = true,
    troll_randomtp = true,
    troll_strip = true,
    troll_invert = true,
    troll_randomped = true,
    troll_chicken = true,
    troll_dance = true,
    troll_invisible = true,
    troll_spin = true,
    troll_shrink = true,
    troll_giant = true,
    troll_clones = true,
    adminJail = true,
    clearPed = true,
    reviveAll = true,
    giveMoneyAll = true,
    clearArea = true,
    announcement = true,
    wipePlayer = true,
    saveTeleportFavorite = true,
    deleteTeleportFavorite = true,
    teleportToFavorite = true,
    teleportPlayerToPlayer = true,
    giveWeaponKit = true,
    editBan = true,
    importBans = true,
    bringVehicle = true,
    toggleVehicleDoors = true,
    toggleVehicleEngine = true,
    setVehicleFuel = true,
    freezeVehicle = true,
    setVehicleLivery = true,
    setVehicleExtra = true,
    setVehicleNeon = true,
    setVehicleWheelSmoke = true,
    setVehiclePaintAdvanced = true,
    setVehicleXenon = true,
    setVehicleModkit = true,
    warpIntoVehicle = true,
    warpOutOfVehicle = true,
    sendReportMessage = true,
    sendReportTemplate = true,
    saveOutfit = true,
    loadOutfit = true,
    deleteOutfit = true,
    toggleAdminHud = true,
    reloadConfig = true,

    -- Presets & pro vehicle tools
    saveSelfPreset = true,
    deleteSelfPreset = true,
    loadSelfPreset = true,
    saveVehicleBuild = true,
    deleteVehicleBuild = true,
    applyVehicleBuild = true,
    addVehicleFavorite = true,
    removeVehicleFavorite = true,

    -- Tickets
    ticketAssign = true,
    ticketReply = true,
    ticketClose = true,
    ticketReopen = true
}

local function _ToNumber(v, min, max)
    local n = tonumber(v)
    if not n then return nil end
    if min and n < min then n = min end
    if max and n > max then n = max end
    return n
end

local function _SanitizeText(v, maxLen, pattern)
    if type(v) ~= 'string' then
        if v == nil then return nil end
        v = tostring(v)
    end
    v = v:gsub('[%c]', ' ')
    v = v:gsub('%s+', ' ')
    v = v:match('^%s*(.-)%s*$') or ''
    if maxLen and #v > maxLen then
        v = v:sub(1, maxLen)
    end
    if pattern and not v:match(pattern) then
        return nil
    end
    return v
end

local function _SanitizeRgbColor(v, default)
    if type(v) ~= 'table' then return default end
    local r = _ToNumber(v.r, 0, 255)
    local g = _ToNumber(v.g, 0, 255)
    local b = _ToNumber(v.b, 0, 255)
    if r == nil or g == nil or b == nil then
        return default
    end
    return { r = math.floor(r), g = math.floor(g), b = math.floor(b) }
end

local function _ClampInt(v, minV, maxV, def)
    local n = tonumber(v)
    if n == nil then return def end
    n = math.floor(n)
    if n < minV then return minV end
    if n > maxV then return maxV end
    return n
end

local function _SanitizeVehicleModkit(mods)
    if type(mods) ~= 'table' then
        return nil
    end

    return {
        engine = _ClampInt(mods.engine, -1, 5, -1),
        brakes = _ClampInt(mods.brakes, -1, 5, -1),
        transmission = _ClampInt(mods.transmission, -1, 5, -1),
        suspension = _ClampInt(mods.suspension, -1, 5, -1),
        armor = _ClampInt(mods.armor, -1, 5, -1),
        turbo = mods.turbo == true or mods.turbo == 1 or mods.turbo == '1' or mods.turbo == 'true'
    }
end

RegisterNUICallback('action', function(data, cb)
    if not isOpen then
        cb({ ok = false, error = 'panel_closed' })
        return
    end

    if type(data) ~= 'table' then
        cb({ ok = false, error = 'invalid_payload' })
        return
    end

    local a = _SanitizeText(data.action, 64, '^[%w_]+$')
    if not a or AllowedPanelActions[a] ~= true then
        cb({ ok = false, error = 'invalid_action' })
        return
    end

    -- Lightweight client-side sanitization (server remains authoritative).
    data.reason = _SanitizeText(data.reason, 250)
    data.message = _SanitizeText(data.message, 500)
    data.note = _SanitizeText(data.note, 400)
    data.model = _SanitizeText(data.model, 64, '^[%w_]+$') or data.model
    data.vehicle = _SanitizeText(data.vehicle, 64, '^[%w_]+$') or data.vehicle
    data.weapon = _SanitizeText(data.weapon, 64, '^[%w_]+$') or data.weapon
    data.item = _SanitizeText(data.item, 64, '^[%w_]+$') or data.item
    data.job = _SanitizeText(data.job, 64, '^[%w_]+$') or data.job
    data.weather = _SanitizeText(data.weather, 32, '^[%w_]+$') or data.weather
    data.account = _SanitizeText(data.account, 32, '^[%w_]+$') or data.account
    data.identifier = _SanitizeText(data.identifier, 128)
    data.playerName = _SanitizeText(data.playerName, 100)
    data.priority = _SanitizeText(data.priority, 16, '^[%w_]+$') or data.priority
    data.templateId = _SanitizeText(data.templateId, 64, '^[%w_%-]+$') or data.templateId
    data.confirmText = _SanitizeText(data.confirmText, 32)
    data.targetId = _ToNumber(data.targetId)
    data.fromId = _ToNumber(data.fromId)
    data.toId = _ToNumber(data.toId)
    data.amount = _ToNumber(data.amount)
    data.time = _ToNumber(data.time)
    data.duration = _ToNumber(data.duration)
    data.durationMs = _ToNumber(data.durationMs)
    data.grade = _ToNumber(data.grade, 0, 50)
    data.hour = _ToNumber(data.hour, 0, 23)
    data.minute = _ToNumber(data.minute, 0, 59)
    data.radius = _ToNumber(data.radius, 1, 1000)
    data.fuelLevel = _ToNumber(data.fuelLevel, 0, 100)
    data.livery = _ToNumber(data.livery, -1, 200)
    data.extraId = _ToNumber(data.extraId, 0, 20)
    data.pearlescent = _ToNumber(data.pearlescent, 0, 160)
    data.wheelColor = _ToNumber(data.wheelColor, 0, 160)
    data.xenonColor = _ToNumber(data.xenonColor, -1, 13)
    data.doorIndex = _ToNumber(data.doorIndex, -1, 7)
    data.driverPlayerId = _ToNumber(data.driverPlayerId)
    data.mods = _SanitizeVehicleModkit(data.mods)
    data.reportId = _ToNumber(data.reportId)
    data.reporterId = _ToNumber(data.reporterId)
    data.ticketId = _ToNumber(data.ticketId)
    data.banId = _ToNumber(data.banId)
    data.favoriteId = _ToNumber(data.favoriteId)
    data.outfitId = _ToNumber(data.outfitId)
    data.player1 = _ToNumber(data.player1)
    data.player2 = _ToNumber(data.player2)
    data.color = _SanitizeRgbColor(data.color, nil)
    data.neonColor = _SanitizeRgbColor(data.neonColor, nil)
    data.smokeColor = _SanitizeRgbColor(data.smokeColor, nil)
    if type(data.targetIds) == 'table' then
        local clean = {}
        local seen = {}
        for i = 1, #data.targetIds do
            local pid = _ToNumber(data.targetIds[i], 1, 4096)
            if pid and not seen[pid] then
                seen[pid] = true
                clean[#clean + 1] = math.floor(pid)
                if #clean >= 32 then
                    break
                end
            end
        end
        data.targetIds = clean
    else
        data.targetIds = nil
    end

    if Config and Config.Debug then
        print('[LyxPanel] Action received from UI:', a)
    end

    -- Bsicas
    if a == 'kick' then
        SendSecureServerEvent('lyxpanel:action:kick', data.targetId, data.reason)
    elseif a == 'ban' then
        SendSecureServerEvent('lyxpanel:action:ban', data.targetId, data.reason, data.duration, data.dryRun)
    elseif a == 'unban' then
        local identifier = _SanitizeText(data.identifier, 128)
        local banId = data.banId or data.targetId
        if identifier and identifier ~= '' then
            SendSecureServerEvent('lyxpanel:action:unban', identifier, data.reason, data.dryRun)
        elseif banId then
            -- Backwards compatibility path (legacy UIs may still send banId/targetId).
            SendSecureServerEvent('lyxpanel:action:unban', banId, data.reason, data.dryRun)
        end
    elseif a == 'warn' then
        SendSecureServerEvent('lyxpanel:action:warn', data.targetId, data.reason)

        -- Economa
    elseif a == 'giveMoney' then
        SendSecureServerEvent('lyxpanel:action:giveMoney', data.targetId, data.account, data.amount, data.dryRun)
    elseif a == 'setMoney' then
        SendSecureServerEvent('lyxpanel:action:setMoney', data.targetId, data.account, data.amount, data.dryRun)
    elseif a == 'removeMoney' then
        SendSecureServerEvent('lyxpanel:action:removeMoney', data.targetId, data.account, data.amount, data.dryRun)
    elseif a == 'transferMoney' then
        SendSecureServerEvent('lyxpanel:action:transferMoney', data.fromId, data.toId, data.account, data.amount, data.dryRun)

        -- Armas/Items
    elseif a == 'giveWeapon' then
        SendSecureServerEvent('lyxpanel:action:giveWeapon', data.targetId, data.weapon, data.ammo)
    elseif a == 'giveAmmo' then
        SendSecureServerEvent('lyxpanel:action:giveAmmo', data.targetId, data.weapon, data.ammo)
    elseif a == 'removeWeapon' then
        SendSecureServerEvent('lyxpanel:action:removeWeapon', data.targetId, data.weapon)
    elseif a == 'removeAllWeapons' then
        SendSecureServerEvent('lyxpanel:action:removeAllWeapons', data.targetId)
    elseif a == 'giveItem' then
        SendSecureServerEvent('lyxpanel:action:giveItem', data.targetId, data.item, data.count)
    elseif a == 'removeItem' then
        SendSecureServerEvent('lyxpanel:action:removeItem', data.targetId, data.item, data.count)
    elseif a == 'clearInventory' then
        SendSecureServerEvent('lyxpanel:action:clearInventory', data.targetId, data.dryRun)

        -- Vehculos
    elseif a == 'spawnVehicle' then
        local vehicleModel = data.model or data.vehicle
        if vehicleModel then
            SendSecureServerEvent('lyxpanel:action:spawnVehicle', data.targetId or -1, vehicleModel)
        end
    elseif a == 'quickSpawnWarpTune' then
        local vehicleModel = data.model or data.vehicle
        if vehicleModel then
            SendSecureServerEvent('lyxpanel:action:quickSpawnWarpTune', data.targetId or -1, vehicleModel)
        end
    elseif a == 'deleteVehicle' then
        SendSecureServerEvent('lyxpanel:action:deleteVehicle', data.targetId)
    elseif a == 'repairVehicle' then
        SendSecureServerEvent('lyxpanel:action:repairVehicle', data.targetId)
    elseif a == 'flipVehicle' then
        SendSecureServerEvent('lyxpanel:action:flipVehicle', data.targetId)
    elseif a == 'boostVehicle' then
        SendSecureServerEvent('lyxpanel:action:boostVehicle', data.targetId)
    elseif a == 'deleteNearby' or a == 'deleteNearbyVehicles' then
        SendSecureServerEvent('lyxpanel:action:deleteNearbyVehicles')
        -- Vehculos Avanzados (v4.1)
    elseif a == 'cleanVehicle' then
        SendSecureServerEvent('lyxpanel:action:cleanVehicle', data.targetId)
    elseif a == 'setVehicleColor' then
        SendSecureServerEvent('lyxpanel:action:setVehicleColor', data.targetId, data.primary, data.secondary)
    elseif a == 'setVehiclePlate' then
        SendSecureServerEvent('lyxpanel:action:setVehiclePlate', data.targetId, data.plate)
    elseif a == 'tuneVehicle' then
        SendSecureServerEvent('lyxpanel:action:tuneVehicle', data.targetId)
    elseif a == 'ghostVehicle' then
        SendSecureServerEvent('lyxpanel:action:ghostVehicle', data.targetId, data.enabled)
    elseif a == 'getVehicleInfo' then
        SendSecureServerEvent('lyxpanel:action:getVehicleInfo')

        -- Teleport
    elseif a == 'teleportTo' then
        SendSecureServerEvent('lyxpanel:action:teleportTo', data.targetId)
    elseif a == 'bring' then
        SendSecureServerEvent('lyxpanel:action:bring', data.targetId)
    elseif a == 'teleportCoords' then
        SendSecureServerEvent('lyxpanel:action:teleportCoords', data.x, data.y, data.z)
    elseif a == 'teleportMarker' then
        SendSecureServerEvent('lyxpanel:action:teleportMarker')
    elseif a == 'teleportBack' then
        SendSecureServerEvent('lyxpanel:action:teleportBack')

        -- Salud
    elseif a == 'heal' then
        SendSecureServerEvent('lyxpanel:action:heal', data.targetId)
    elseif a == 'revive' then
        SendSecureServerEvent('lyxpanel:action:revive', data.targetId)
    elseif a == 'reviveRadius' then
        SendSecureServerEvent('lyxpanel:action:reviveRadius', data.radius, data.dryRun)
    elseif a == 'setArmor' then
        SendSecureServerEvent('lyxpanel:action:setArmor', data.targetId, data.amount)
    elseif a == 'setHealth' then
        SendSecureServerEvent('lyxpanel:action:setHealth', data.targetId, data.amount)

        -- Control
    elseif a == 'freeze' then
        SendSecureServerEvent('lyxpanel:action:freeze', data.targetId, data.freeze)
    elseif a == 'spectate' then
        SendSecureServerEvent('lyxpanel:action:spectate', data.targetId)
    elseif a == 'kill' then
        SendSecureServerEvent('lyxpanel:action:kill', data.targetId)
    elseif a == 'slap' then
        SendSecureServerEvent('lyxpanel:action:slap', data.targetId)
    elseif a == 'ragdoll' then
        SendSecureServerEvent('lyxpanel:action:ragdoll', data.targetId, data.durationMs or data.duration)

        -- Jail / Mute (server/actions_extended.lua)
    elseif a == 'jail' then
        SendSecureServerEvent('lyxpanel:action:jail', data.targetId, data.time, data.reason)
    elseif a == 'unjail' then
        SendSecureServerEvent('lyxpanel:action:unjail', data.targetId)
    elseif a == 'muteChat' then
        SendSecureServerEvent('lyxpanel:action:muteChat', data.targetId, data.time)
    elseif a == 'muteVoice' then
        SendSecureServerEvent('lyxpanel:action:muteVoice', data.targetId, data.time)
    elseif a == 'unmute' then
        SendSecureServerEvent('lyxpanel:action:unmute', data.targetId)

        -- Job
    elseif a == 'setJob' then
        SendSecureServerEvent('lyxpanel:action:setJob', data.targetId, data.job, data.grade)

        -- Admin
    elseif a == 'noclip' then
        SendSecureServerEvent('lyxpanel:action:noclip')
    elseif a == 'godmode' then
        SendSecureServerEvent('lyxpanel:action:godmode')
    elseif a == 'invisible' then
        SendSecureServerEvent('lyxpanel:action:invisible')
    elseif a == 'speedboost' then
        SendSecureServerEvent('lyxpanel:action:speedboost')
    elseif a == 'nitro' then
        SendSecureServerEvent('lyxpanel:action:nitro')
    elseif a == 'vehicleGodmode' then
        SendSecureServerEvent('lyxpanel:action:vehicleGodmode')

        -- Comunicacin
    elseif a == 'announce' then
        SendSecureServerEvent('lyxpanel:action:announce', data.message, data.type)
    elseif a == 'privateMessage' then
        SendSecureServerEvent('lyxpanel:action:privateMessage', data.targetId, data.message)
    elseif a == 'adminChat' then
        SendSecureServerEvent('lyxpanel:action:adminChat', data.message)

        -- Notas
    elseif a == 'addNote' then
        SendSecureServerEvent('lyxpanel:action:addNote', data.targetId, data.note)

        -- Mundo
    elseif a == 'setWeather' then
        SendSecureServerEvent('lyxpanel:action:setWeather', data.weather)
    elseif a == 'setTime' then
        SendSecureServerEvent('lyxpanel:action:setTime', data.hour, data.minute)

        -- Whitelist
    elseif a == 'addWhitelist' then
        SendSecureServerEvent('lyxpanel:action:addWhitelist', data.identifier, data.playerName)
    elseif a == 'removeWhitelist' then
        local idOrIdentifier = data.id or data.identifier
        SendSecureServerEvent('lyxpanel:action:removeWhitelist', idOrIdentifier)

        -- Reportes/Bans
    elseif a == 'assignReport' then
        SendSecureServerEvent('lyxpanel:action:assignReport', data.reportId)
    elseif a == 'tpToReporter' then
        SendSecureServerEvent('lyxpanel:action:tpToReporter', data.reporterId)
    elseif a == 'closeReport' then
        SendSecureServerEvent('lyxpanel:action:closeReport', data.reportId, data.notes)
    elseif a == 'setReportPriority' then
        SendSecureServerEvent('lyxpanel:action:setReportPriority', data.reportId, data.priority)

        -- Logs & Detections
    elseif a == 'clearLogs' then
        SendSecureServerEvent('lyxpanel:action:clearLogs', data.reason, data.dryRun)
    elseif a == 'clearAllDetections' then
        SendSecureServerEvent('lyxpanel:action:clearAllDetections', data.reason, data.dryRun)

        -- Model
    elseif a == 'changeModel' then
        SendSecureServerEvent('lyxpanel:action:changeModel', data.targetId, data.model)

    -- Screenshot
    elseif a == 'screenshot' then
        SendSecureServerEvent('lyxpanel:action:screenshot', data.targetId)
    elseif a == 'screenshotBatch' then
        SendSecureServerEvent('lyxpanel:action:screenshotBatch', data.targetIds)

        -- ...............................................................................
        -- TROLLEO ACTIONS
        -- ...............................................................................
    elseif a == 'troll_explode' then
        SendSecureServerEvent('lyxpanel:action:troll:explode', data.targetId)
    elseif a == 'troll_fire' then
        SendSecureServerEvent('lyxpanel:action:troll:fire', data.targetId)
    elseif a == 'troll_launch' then
        SendSecureServerEvent('lyxpanel:action:troll:launch', data.targetId, data.force)
    elseif a == 'troll_ragdoll' then
        SendSecureServerEvent('lyxpanel:action:troll:ragdoll', data.targetId)
    elseif a == 'troll_drunk' then
        SendSecureServerEvent('lyxpanel:action:troll:drunk', data.targetId, data.duration or 30)
    elseif a == 'troll_drug' then
        SendSecureServerEvent('lyxpanel:action:troll:drugScreen', data.targetId, data.duration or 20)
    elseif a == 'troll_blackscreen' then
        SendSecureServerEvent('lyxpanel:action:troll:blackScreen', data.targetId, data.duration or 10)
    elseif a == 'troll_scream' then
        SendSecureServerEvent('lyxpanel:action:troll:scream', data.targetId)
    elseif a == 'troll_randomtp' then
        SendSecureServerEvent('lyxpanel:action:troll:randomTeleport', data.targetId)
    elseif a == 'troll_strip' then
        SendSecureServerEvent('lyxpanel:action:troll:stripClothes', data.targetId)
    elseif a == 'troll_invert' then
        SendSecureServerEvent('lyxpanel:action:troll:invertControls', data.targetId, data.duration or 15)
    elseif a == 'troll_randomped' then
        SendSecureServerEvent('lyxpanel:action:troll:randomPed', data.targetId)
    elseif a == 'troll_chicken' then
        SendSecureServerEvent('lyxpanel:action:troll:chicken', data.targetId)
    elseif a == 'troll_dance' then
        SendSecureServerEvent('lyxpanel:action:troll:dance', data.targetId)
        -- Nuevos trolls avanzados
    elseif a == 'troll_invisible' then
        SendSecureServerEvent('lyxpanel:action:troll:invisible', data.targetId, data.duration or 30)
    elseif a == 'troll_spin' then
        SendSecureServerEvent('lyxpanel:action:troll:spin', data.targetId, data.duration or 15)
    elseif a == 'troll_shrink' then
        SendSecureServerEvent('lyxpanel:action:troll:shrink', data.targetId, data.duration or 60)
    elseif a == 'troll_giant' then
        SendSecureServerEvent('lyxpanel:action:troll:giant', data.targetId, data.duration or 30)
    elseif a == 'troll_clones' then
        SendSecureServerEvent('lyxpanel:action:troll:clones', data.targetId, data.count or 5)

        -- v4.2 NEW FEATURES
    elseif a == 'adminJail' then
        SendSecureServerEvent('lyxpanel:action:adminJail', data.targetId, data.duration or 300, data.dryRun)
    elseif a == 'clearPed' then
        SendSecureServerEvent('lyxpanel:action:clearPed', data.targetId, data.dryRun)
    elseif a == 'reviveAll' then
        SendSecureServerEvent('lyxpanel:action:reviveAll', data.dryRun)
    elseif a == 'giveMoneyAll' then
        SendSecureServerEvent('lyxpanel:action:giveMoneyAll', data.amount, data.accountType, data.dryRun)
    elseif a == 'clearArea' then
        SendSecureServerEvent('lyxpanel:action:clearArea', data.radius, data.dryRun)
    elseif a == 'announcement' then
        SendSecureServerEvent('lyxpanel:action:announcement', data.message, data.dryRun)
    elseif a == 'wipePlayer' then
        SendSecureServerEvent('lyxpanel:action:wipePlayer', data.targetId, data.confirmText, data.reason, data.dryRun)

    -- ...............................................................................
    -- v4.5 NEW FEATURES
    -- ...............................................................................

    -- Teleport favorites
    elseif a == 'saveTeleportFavorite' then
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        SendSecureServerEvent('lyxpanel:action:saveTeleportFavorite', data.name, {
            x = coords.x, y = coords.y, z = coords.z, heading = GetEntityHeading(ped)
        })
    elseif a == 'deleteTeleportFavorite' then
        SendSecureServerEvent('lyxpanel:action:deleteTeleportFavorite', data.favoriteId)
    elseif a == 'teleportToFavorite' then
        SendSecureServerEvent('lyxpanel:action:teleportToFavorite', data.location)
    elseif a == 'teleportPlayerToPlayer' then
        SendSecureServerEvent('lyxpanel:action:teleportPlayerToPlayer', data.player1, data.player2)

    -- Weapon kits
    elseif a == 'giveWeaponKit' then
        SendSecureServerEvent('lyxpanel:action:giveWeaponKit', data.targetId, data.kitId, data.dryRun)

    -- Ban management
    elseif a == 'editBan' then
        SendSecureServerEvent('lyxpanel:action:editBan', data.banId, data.reason, data.duration)
    elseif a == 'importBans' then
        SendSecureServerEvent('lyxpanel:action:importBans', data.bans, data.dryRun)

    -- Vehicle advanced
    elseif a == 'bringVehicle' then
        SendSecureServerEvent('lyxpanel:action:bringVehicle', data.targetId)
    elseif a == 'toggleVehicleDoors' then
        SendSecureServerEvent('lyxpanel:action:toggleVehicleDoors', data.targetId, data.doorIndex or -1)
    elseif a == 'toggleVehicleEngine' then
        SendSecureServerEvent('lyxpanel:action:toggleVehicleEngine', data.targetId)
    elseif a == 'setVehicleFuel' then
        SendSecureServerEvent('lyxpanel:action:setVehicleFuel', data.targetId, data.fuelLevel)
    elseif a == 'freezeVehicle' then
        SendSecureServerEvent('lyxpanel:action:freezeVehicle', data.targetId, data.enabled)
    elseif a == 'setVehicleLivery' then
        SendSecureServerEvent('lyxpanel:action:setVehicleLivery', data.targetId, data.livery)
    elseif a == 'setVehicleExtra' then
        SendSecureServerEvent('lyxpanel:action:setVehicleExtra', data.targetId, data.extraId, data.enabled)
    elseif a == 'setVehicleNeon' then
        SendSecureServerEvent('lyxpanel:action:setVehicleNeon', data.targetId, data.enabled, data.neonColor or data.color)
    elseif a == 'setVehicleWheelSmoke' then
        SendSecureServerEvent('lyxpanel:action:setVehicleWheelSmoke', data.targetId, data.smokeColor or data.color)
    elseif a == 'setVehiclePaintAdvanced' then
        SendSecureServerEvent('lyxpanel:action:setVehiclePaintAdvanced', data.targetId, data.pearlescent, data.wheelColor)
    elseif a == 'setVehicleXenon' then
        SendSecureServerEvent('lyxpanel:action:setVehicleXenon', data.targetId, data.enabled, data.xenonColor)
    elseif a == 'setVehicleModkit' then
        if data.mods then
            SendSecureServerEvent('lyxpanel:action:setVehicleModkit', data.targetId, data.mods)
        end
    elseif a == 'warpIntoVehicle' then
        SendSecureServerEvent('lyxpanel:action:warpIntoVehicle', data.targetId, data.driverPlayerId)
    elseif a == 'warpOutOfVehicle' then
        SendSecureServerEvent('lyxpanel:action:warpOutOfVehicle', data.targetId)

    -- Report priority
    elseif a == 'setReportPriority' then
        SendSecureServerEvent('lyxpanel:action:setReportPriority', data.reportId, data.priority)
    elseif a == 'sendReportMessage' then
        SendSecureServerEvent('lyxpanel:action:sendReportMessage', data.reportId, data.targetId, data.message)
    elseif a == 'sendReportTemplate' then
        SendSecureServerEvent('lyxpanel:action:sendReportTemplate', data.reportId, data.targetId, data.templateId)

    -- Tickets (support)
    elseif a == 'ticketAssign' then
        SendSecureServerEvent('lyxpanel:action:ticketAssign', data.ticketId)
    elseif a == 'ticketReply' then
        SendSecureServerEvent('lyxpanel:action:ticketReply', data.ticketId, data.message)
    elseif a == 'ticketClose' then
        SendSecureServerEvent('lyxpanel:action:ticketClose', data.ticketId, data.reason)
    elseif a == 'ticketReopen' then
        SendSecureServerEvent('lyxpanel:action:ticketReopen', data.ticketId)

    -- Presets / pro tools
    elseif a == 'saveSelfPreset' then
        SendSecureServerEvent('lyxpanel:action:saveSelfPreset', data.name, data.data)
    elseif a == 'deleteSelfPreset' then
        SendSecureServerEvent('lyxpanel:action:deleteSelfPreset', data.presetId)
    elseif a == 'loadSelfPreset' then
        SendSecureServerEvent('lyxpanel:action:loadSelfPreset', data.presetId)
    elseif a == 'saveVehicleBuild' then
        SendSecureServerEvent('lyxpanel:action:saveVehicleBuild', data.name, data.build)
    elseif a == 'deleteVehicleBuild' then
        SendSecureServerEvent('lyxpanel:action:deleteVehicleBuild', data.buildId)
    elseif a == 'applyVehicleBuild' then
        SendSecureServerEvent('lyxpanel:action:applyVehicleBuild', data.buildId)
    elseif a == 'addVehicleFavorite' then
        SendSecureServerEvent('lyxpanel:action:addVehicleFavorite', data.model, data.label)
    elseif a == 'removeVehicleFavorite' then
        SendSecureServerEvent('lyxpanel:action:removeVehicleFavorite', data.favoriteId)

    -- Outfits
    elseif a == 'saveOutfit' then
        -- Get current outfit from client
        local ped = PlayerPedId()
        local outfitData = {}
        for i = 0, 11 do
            outfitData['comp_' .. i] = {
                drawable = GetPedDrawableVariation(ped, i),
                texture = GetPedTextureVariation(ped, i)
            }
        end
        for i = 0, 8 do
            outfitData['prop_' .. i] = {
                drawable = GetPedPropIndex(ped, i),
                texture = GetPedPropTextureIndex(ped, i)
            }
        end
        SendSecureServerEvent('lyxpanel:action:saveOutfit', data.name, outfitData)
    elseif a == 'loadOutfit' then
        SendSecureServerEvent('lyxpanel:action:loadOutfit', data.outfitId)
    elseif a == 'deleteOutfit' then
        SendSecureServerEvent('lyxpanel:action:deleteOutfit', data.outfitId)

    -- Admin HUD
    elseif a == 'toggleAdminHud' then
        TriggerEvent('lyxpanel:toggleAdminHud', data.enabled)

    -- Reload config
    elseif a == 'reloadConfig' then
        SendSecureServerEvent('lyxpanel:action:reloadConfig')
    end

    cb({})
end)

-- ...............................................................................
-- EVENTOS CLIENTE
-- ...............................................................................

RegisterNetEvent('lyxpanel:teleport', function(x, y, z)
    SetEntityCoords(PlayerPedId(), x, y, z, false, false, false, false)
end)

RegisterNetEvent('lyxpanel:teleportMarker', function()
    local blip = GetFirstBlipInfoId(8)
    if DoesBlipExist(blip) then
        local c = GetBlipInfoIdCoord(blip)
        local _, groundZ = GetGroundZFor_3dCoord(c.x, c.y, 1000.0, true)
        SetEntityCoords(PlayerPedId(), c.x, c.y, groundZ + 1.0, false, false, false, false)
    end
end)

RegisterNetEvent('lyxpanel:heal', function()
    print('[LyxPanel] HEAL event received!')
    local ped = PlayerPedId()

    if IsPedDeadOrDying(ped, true) or IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then
        TriggerEvent('lyxpanel:revive')
        local t = GetGameTimer() + 1500
        while GetGameTimer() < t do
            Wait(50)
            ped = PlayerPedId()
            if ped and ped ~= 0 and (not IsPedDeadOrDying(ped, true)) and (not IsEntityDead(ped)) and GetEntityHealth(ped) > 0 then
                break
            end
        end
    end

    local currentHealth = GetEntityHealth(ped)
    local maxHealth = GetEntityMaxHealth(ped)
    print('[LyxPanel] Current health:', currentHealth, 'Max:', maxHealth)

    -- Restaurar salud completa (mtodo txAdmin)
    SetEntityHealth(ped, maxHealth)

    -- Limpiar efectos visuales
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)

    -- Si el jugador estaba con ragdoll, resetearlo
    if IsPedRagdoll(ped) then
        SetPedToRagdoll(ped, 0, 0, 0, false, false, false)
    end

    print('[LyxPanel] HEAL complete! New health:', GetEntityHealth(ped))
end)

RegisterNetEvent('lyxpanel:revive', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- 1. Detener estados de muerte de GTA (mtodo txAdmin)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)

    -- 2. Esperar un frame para que el nativo surta efecto
    Wait(0)
    ped = PlayerPedId()

    -- 3. Restaurar salud y armadura
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 0)

    -- 4. Limpiar efectos visuales y estados de muerte
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
    ResetPedVisibleDamage(ped)
    ClearPlayerWantedLevel(PlayerId())

    -- 5. Detener efectos de muerte
    AnimpostfxStop('DeathFailOut')
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    -- 6. Asegurar que el jugador no est invincible atrapado
    SetPlayerInvincible(PlayerId(), false)
    SetEntityInvincible(ped, false)

    -- 7. Teleport ligeramente hacia arriba para evitar quedar atrapado
    SetEntityCoords(ped, coords.x, coords.y, coords.z + 0.5, false, false, false, false)

    -- 8. Notificar scripts de muerte/ambulancia (multi-sistema)
    -- brutal_ambulancejob
    if GetResourceState('brutal_ambulancejob') == 'started' then
        TriggerEvent('brutal_ambulancejob:revive')
        TriggerEvent('brutal_ambulancejob:client:Revive')
    end

    -- esx_ambulancejob
    if GetResourceState('esx_ambulancejob') == 'started' then
        TriggerEvent('esx_ambulancejob:revive')
    end

    -- wasabi_ambulance
    if GetResourceState('wasabi_ambulance') == 'started' then
        TriggerEvent('wasabi_ambulance:revive')
    end

    -- ars_ambulancejob
    if GetResourceState('ars_ambulancejob') == 'started' then
        TriggerEvent('ars_ambulancejob:revive')
    end

    -- qb-ambulancejob (para compatibilidad)
    if GetResourceState('qb-ambulancejob') == 'started' then
        TriggerEvent('hospital:client:Revive')
    end

    -- 9. Notificar txAdmin
    TriggerEvent('txAdmin:client:HealPlayer')

    -- 10. Esperar y re-aplicar salud por si acaso
    Wait(100)
    ped = PlayerPedId()
    if GetEntityHealth(ped) < 200 then
        SetEntityHealth(ped, 200)
    end

    -- 11. Forzar levantarse de cualquier estado
    ClearPedTasks(ped)
    SetEntityCollision(ped, true, true)
end)

-- Dar municin a un arma existente
RegisterNetEvent('lyxpanel:giveAmmo', function(weapon, ammo)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon)

    if HasPedGotWeapon(ped, weaponHash, false) then
        -- Aadir municin al arma
        AddAmmoToPed(ped, weaponHash, ammo)
    else
        -- Si no tiene el arma, darle el arma con la municin
        GiveWeaponToPed(ped, weaponHash, ammo, false, true)
    end
end)

RegisterNetEvent('lyxpanel:setArmor', function(amount)
    SetPedArmour(PlayerPedId(), amount)
end)

RegisterNetEvent('lyxpanel:setHealth', function(amount)
    SetEntityHealth(PlayerPedId(), amount)
end)

RegisterNetEvent('lyxpanel:freeze', function(freeze)
    FreezeEntityPosition(PlayerPedId(), freeze)
end)

RegisterNetEvent('lyxpanel:removeAllWeapons', function()
    RemoveAllPedWeapons(PlayerPedId(), true)
end)

-- Evento para recibir arma directamente del admin panel (asegura recepcin inmediata)
RegisterNetEvent('lyxpanel:giveWeaponDirect', function(weapon, ammo)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon)

    -- Cargar el modelo del arma si es necesario
    RequestWeaponAsset(weaponHash, 31, 0)
    while not HasWeaponAssetLoaded(weaponHash) do
        Wait(10)
    end

    -- Dar el arma con el nativo de GTA
    GiveWeaponToPed(ped, weaponHash, ammo or 250, false, true)

    -- Asegurar que el jugador tenga la municin
    SetPedAmmo(ped, weaponHash, ammo or 250)

    -- Equipar el arma automticamente
    SetCurrentPedWeapon(ped, weaponHash, true)
end)

RegisterNetEvent('lyxpanel:clearInventory', function()
    TriggerEvent('esx:removeInventory')
end)

RegisterNetEvent('lyxpanel:kill', function()
    SetEntityHealth(PlayerPedId(), 0)
end)

RegisterNetEvent('lyxpanel:slap', function()
    local ped = PlayerPedId()
    -- Aplicar velocidad hacia arriba
    SetEntityVelocity(ped, 0.0, 0.0, 15.0)
    -- Aplicar ragdoll por un momento
    SetPedToRagdoll(ped, 2000, 2000, 0, false, false, false)
    -- Quitar un poco de vida
    local health = GetEntityHealth(ped)
    if health > 30 then
        SetEntityHealth(ped, health - 25)
    end
end)

RegisterNetEvent('lyxpanel:ragdoll', function(durationMs)
    local ped = PlayerPedId()
    durationMs = tonumber(durationMs) or 5000
    if durationMs < 500 then durationMs = 500 end
    if durationMs > 15000 then durationMs = 15000 end
    SetPedToRagdoll(ped, durationMs, durationMs, 0, false, false, false)
end)


-- Vehculos
RegisterNetEvent('lyxpanel:spawnVehicle', function(model)
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local veh = CreateVehicle(hash, c.x, c.y, c.z, h, true, false)
    TaskWarpPedIntoVehicle(ped, veh, -1)
    SetVehicleNumberPlateText(veh, 'ADMIN')
    SetVehicleColours(veh, 0, 0)
    SetModelAsNoLongerNeeded(hash)
end)

RegisterNetEvent('lyxpanel:quickSpawnWarpTune', function(model)
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)

    local veh = CreateVehicle(hash, c.x, c.y, c.z, h, true, false)
    if veh ~= 0 then
        TaskWarpPedIntoVehicle(ped, veh, -1)
        SetVehicleModKit(veh, 0)
        SetVehicleFixed(veh)
        SetVehicleDirtLevel(veh, 0.0)
        SetVehicleNumberPlateText(veh, 'LYXFAST')

        local function _MaxMod(modType)
            local max = GetNumVehicleMods(veh, modType)
            if max and max > 0 then
                SetVehicleMod(veh, modType, max - 1, false)
            end
        end

        _MaxMod(11) -- engine
        _MaxMod(12) -- brakes
        _MaxMod(13) -- transmission
        _MaxMod(15) -- suspension
        _MaxMod(16) -- armor
        ToggleVehicleMod(veh, 18, true) -- turbo
        ToggleVehicleMod(veh, 22, true) -- xenon
    end

    SetModelAsNoLongerNeeded(hash)
end)

-- Apply vehicle build preset (server sends validated build table).
RegisterNetEvent('lyxpanel:vehicle:applyBuild', function(build)
    if type(build) ~= 'table' then return end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        TriggerEvent('chat:addMessage', { args = { 'LyxPanel', 'No estas en un vehiculo para aplicar el build.' } })
        return
    end

    SetVehicleModKit(veh, 0)

    if type(build.plate) == 'string' and build.plate ~= '' then
        local plate = tostring(build.plate):upper():gsub('[^A-Z0-9]', ''):sub(1, 8)
        if plate ~= '' then
            SetVehicleNumberPlateText(veh, plate)
        end
    end

    if type(build.primary) == 'table' and build.primary.r and build.primary.g and build.primary.b then
        SetVehicleCustomPrimaryColour(veh, tonumber(build.primary.r) or 0, tonumber(build.primary.g) or 0,
            tonumber(build.primary.b) or 0)
    elseif type(build.primary) == 'number' then
        local _, sec = GetVehicleColours(veh)
        SetVehicleColours(veh, tonumber(build.primary) or 0, sec or 0)
    end

    if type(build.secondary) == 'table' and build.secondary.r and build.secondary.g and build.secondary.b then
        SetVehicleCustomSecondaryColour(veh, tonumber(build.secondary.r) or 0, tonumber(build.secondary.g) or 0,
            tonumber(build.secondary.b) or 0)
    elseif type(build.secondary) == 'number' then
        local pri, _ = GetVehicleColours(veh)
        SetVehicleColours(veh, pri or 0, tonumber(build.secondary) or 0)
    end

    if type(build.pearlescent) == 'number' or type(build.wheelColor) == 'number' then
        local pearl = type(build.pearlescent) == 'number' and build.pearlescent or 0
        local wheel = type(build.wheelColor) == 'number' and build.wheelColor or 0
        SetVehicleExtraColours(veh, pearl, wheel)
    end

    if type(build.livery) == 'number' then
        SetVehicleLivery(veh, build.livery)
    end

    if type(build.neonEnabled) == 'boolean' then
        for i = 0, 3 do
            SetVehicleNeonLightEnabled(veh, i, build.neonEnabled)
        end
    end
    if type(build.neonColor) == 'table' and build.neonColor.r and build.neonColor.g and build.neonColor.b then
        SetVehicleNeonLightsColour(veh, tonumber(build.neonColor.r) or 0, tonumber(build.neonColor.g) or 0,
            tonumber(build.neonColor.b) or 0)
    end

    if type(build.smokeColor) == 'table' and build.smokeColor.r and build.smokeColor.g and build.smokeColor.b then
        ToggleVehicleMod(veh, 20, true) -- tyre smoke
        SetVehicleTyreSmokeColor(veh, tonumber(build.smokeColor.r) or 0, tonumber(build.smokeColor.g) or 0,
            tonumber(build.smokeColor.b) or 0)
    end

    if type(build.xenonEnabled) == 'boolean' then
        ToggleVehicleMod(veh, 22, build.xenonEnabled)
    end
    if type(build.xenonColor) == 'number' then
        SetVehicleXenonLightsColour(veh, tonumber(build.xenonColor) or -1)
    end

    if type(build.mods) == 'table' then
        if type(build.mods.engine) == 'number' then SetVehicleMod(veh, 11, build.mods.engine, false) end
        if type(build.mods.brakes) == 'number' then SetVehicleMod(veh, 12, build.mods.brakes, false) end
        if type(build.mods.transmission) == 'number' then SetVehicleMod(veh, 13, build.mods.transmission, false) end
        if type(build.mods.suspension) == 'number' then SetVehicleMod(veh, 15, build.mods.suspension, false) end
        if type(build.mods.armor) == 'number' then SetVehicleMod(veh, 16, build.mods.armor, false) end
        if type(build.mods.turbo) == 'boolean' then ToggleVehicleMod(veh, 18, build.mods.turbo) end
    end

    if type(build.extras) == 'table' then
        for k, v in pairs(build.extras) do
            local id = tonumber(k)
            if id and id >= 0 and id <= 20 and DoesExtraExist(veh, id) then
                SetVehicleExtra(veh, id, v == true and 0 or 1)
            end
        end
    end
end)

-- Self preset loaded (server sends validated preset data). Apply via existing server actions.
RegisterNetEvent('lyxpanel:selfPresetLoaded', function(preset)
    if type(preset) ~= 'table' then return end

    if preset.health ~= nil then
        SendSecureServerEvent('lyxpanel:action:setHealth', -1, preset.health)
    end
    if preset.armor ~= nil then
        SendSecureServerEvent('lyxpanel:action:setArmor', -1, preset.armor)
    end

    if type(preset.noclip) == 'boolean' then
        if (preset.noclip == true) ~= (noclipActive == true) then
            SendSecureServerEvent('lyxpanel:action:noclip')
        end
    end

    local wantGod = false
    if type(preset.godmodeMode) == 'string' and preset.godmodeMode:lower() ~= 'off' then
        wantGod = true
    end
    if (wantGod == true) ~= (godmodeActive == true) then
        SendSecureServerEvent('lyxpanel:action:godmode')
    end

    if type(preset.invisible) == 'boolean' then
        if (preset.invisible == true) ~= (invisibleActive == true) then
            SendSecureServerEvent('lyxpanel:action:invisible')
        end
    end
end)

RegisterNetEvent('lyxpanel:deleteVehicle', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then DeleteEntity(veh) end
end)

RegisterNetEvent('lyxpanel:repairVehicle:legacy', function()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        SetVehicleFixed(veh)
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehicleDeformationFixed(veh)
        SetVehicleDirtLevel(veh, 0.0)
    end
end)

RegisterNetEvent('lyxpanel:flipVehicle', function()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        SetEntityRotation(veh, 0.0, 0.0, GetEntityHeading(veh), 0, true)
        SetVehicleOnGroundProperly(veh)
    end
end)

RegisterNetEvent('lyxpanel:boostVehicle', function()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        SetVehicleEnginePowerMultiplier(veh, 50.0)
        SetVehicleEngineTorqueMultiplier(veh, 50.0)
    end
end)

RegisterNetEvent('lyxpanel:deleteNearbyVehicles', function()
    local pos = GetEntityCoords(PlayerPedId())
    local vehs = GetGamePool('CVehicle')
    for _, veh in ipairs(vehs) do
        if #(pos - GetEntityCoords(veh)) < 50.0 and not IsPedInVehicle(PlayerPedId(), veh, false) then
            DeleteEntity(veh)
        end
    end
end)

-- ...............................................................................
-- VEHCULOS AVANZADOS (v4.1)
-- ...............................................................................

-- Limpiar vehculo (suciedad y dao visual)
RegisterNetEvent('lyxpanel:cleanVehicle', function()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        SetVehicleDirtLevel(veh, 0.0)
        WashDecalsFromVehicle(veh, 1.0)
        SetVehicleDeformationFixed(veh)
    end
end)

-- Cambiar color del vehculo
RegisterNetEvent('lyxpanel:setVehicleColor', function(primary, secondary)
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        if type(primary) == 'table' and primary.r and primary.g and primary.b then
            SetVehicleCustomPrimaryColour(veh, tonumber(primary.r) or 255, tonumber(primary.g) or 0, tonumber(primary.b) or 0)
        else
            SetVehicleColours(veh, tonumber(primary) or 0, tonumber(secondary) or 0)
        end

        if type(secondary) == 'table' and secondary.r and secondary.g and secondary.b then
            SetVehicleCustomSecondaryColour(veh, tonumber(secondary.r) or 0, tonumber(secondary.g) or 0, tonumber(secondary.b) or 0)
        end
    end
end)

-- Cambiar placa del vehculo actual
RegisterNetEvent('lyxpanel:setVehiclePlate', function(plate)
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        plate = tostring(plate or ''):upper():gsub('[^A-Z0-9]', ''):sub(1, 8)
        if plate ~= '' then
            SetVehicleNumberPlateText(veh, plate)
        end
    end
end)

-- Tunear vehculo al mximo
RegisterNetEvent('lyxpanel:tuneVehicle', function()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        -- Performance mods
        SetVehicleModKit(veh, 0)
        for i = 0, 49 do
            local max = GetNumVehicleMods(veh, i)
            if max > 0 then
                SetVehicleMod(veh, i, max - 1, false)
            end
        end
        -- Toggle mods
        ToggleVehicleMod(veh, 18, true) -- Turbo
        ToggleVehicleMod(veh, 20, true) -- Bulletproof tires
        ToggleVehicleMod(veh, 22, true) -- Xenon lights
        -- Performance extras
        SetVehicleEnginePowerMultiplier(veh, 10.0)
        SetVehicleEngineTorqueMultiplier(veh, 10.0)
        -- Windows and extras
        for i = 0, 10 do
            SetVehicleExtra(veh, i, false)
        end
        -- Fully repair
        SetVehicleFixed(veh)
    end
end)

-- Estado de ghost para el vehculo actual
local vehicleGhostMode = false

-- Modo fantasma (sin colisin)
RegisterNetEvent('lyxpanel:ghostVehicle', function(enabled)
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        vehicleGhostMode = enabled
        if enabled then
            SetEntityAlpha(veh, 150, false)
            SetEntityCollision(veh, false, false)
        else
            SetEntityAlpha(veh, 255, false)
            SetEntityCollision(veh, true, true)
        end
    end
end)

-- Obtener informacin del vehculo actual para NUI
RegisterNetEvent('lyxpanel:getVehicleInfo', function()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
        local info = {
            model = GetDisplayNameFromVehicleModel(GetEntityModel(veh)),
            plate = GetVehicleNumberPlateText(veh),
            health = math.floor(GetEntityHealth(veh)),
            engineHealth = math.floor(GetVehicleEngineHealth(veh)),
            bodyHealth = math.floor(GetVehicleBodyHealth(veh)),
            dirty = GetVehicleDirtLevel(veh),
            primaryColor = nil,
            secondaryColor = nil
        }
        local p, s = GetVehicleColours(veh)
        info.primaryColor = p
        info.secondaryColor = s
        SendNUIMessage({ action = 'vehicleInfo', data = info })
    end
end)

-- Admin toggles
RegisterNetEvent('lyxpanel:toggleNoclip', function()
    noclipActive = not noclipActive
    SetEntityVisible(PlayerPedId(), not noclipActive, false)
    SetEntityCollision(PlayerPedId(), not noclipActive, not noclipActive)
    FreezeEntityPosition(PlayerPedId(), noclipActive)
end)

RegisterNetEvent('lyxpanel:toggleGodmode', function()
    godmodeActive = not godmodeActive
    SetEntityInvincible(PlayerPedId(), godmodeActive)
    -- NOTA: La inmunidad al anti-cheat se maneja servidor-lado
    -- basado en permisos, NO por peticin del cliente
end)

RegisterNetEvent('lyxpanel:toggleInvisible', function()
    invisibleActive = not invisibleActive
    SetEntityVisible(PlayerPedId(), not invisibleActive, false)
end)

-- Speed boost toggle
RegisterNetEvent('lyxpanel:toggleSpeedboost', function()
    speedboostActive = not speedboostActive
    local playerId = PlayerId()
    if speedboostActive then
        SetRunSprintMultiplierForPlayer(playerId, 1.49)
        SetSwimMultiplierForPlayer(playerId, 1.49)
    else
        SetRunSprintMultiplierForPlayer(playerId, 1.0)
        SetSwimMultiplierForPlayer(playerId, 1.0)
    end
end)

-- Nitro toggle
RegisterNetEvent('lyxpanel:toggleNitro', function()
    nitroActive = not nitroActive
end)

-- Nitro loop
CreateThread(function()
    while true do
        if nitroActive then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                if IsControlPressed(0, 71) then -- W key
                    SetVehicleCurrentRpm(vehicle, 1.0)
                    SetVehicleEngineTorqueMultiplier(vehicle, 3.0)
                    SetVehicleCheatPowerIncrease(vehicle, 1.5)
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- Vehicle godmode toggle
RegisterNetEvent('lyxpanel:toggleVehicleGodmode', function()
    vehicleGodmodeActive = not vehicleGodmodeActive
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        SetEntityInvincible(vehicle, vehicleGodmodeActive)
        SetVehicleCanBeVisiblyDamaged(vehicle, not vehicleGodmodeActive)
        SetVehicleEngineCanDegrade(vehicle, not vehicleGodmodeActive)
        SetVehicleWheelsCanBreak(vehicle, not vehicleGodmodeActive)
    end
end)

-- Vehicle godmode maintenance loop
CreateThread(function()
    while true do
        if vehicleGodmodeActive then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 then
                SetEntityInvincible(vehicle, true)
                SetVehicleFixed(vehicle)
                SetVehicleEngineHealth(vehicle, 1000.0)
                SetVehicleBodyHealth(vehicle, 1000.0)
            end
            Wait(100)
        else
            Wait(500)
        end
    end
end)

RegisterNetEvent('lyxpanel:spectate', function(targetId, coords)
    TriggerEvent('lyxpanel:spectate:start', targetId, coords)
end)

-- Comunicacin
RegisterNetEvent('lyxpanel:announce', function(message, aType)
    -- Notificacin nativa
    SetNotificationTextEntry('STRING')
    AddTextComponentString('Y" ANUNCIO: ' .. message)
    DrawNotification(true, true)

    -- Sonido de notificacin
    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)

    -- Mostrar en pantalla con efecto mejorado
    CreateThread(function()
        local duration = 8000 -- 8 segundos
        local startTime = GetGameTimer()
        local colors = {
            info = { 66, 135, 245 },
            warning = { 245, 158, 66 },
            error = { 245, 66, 66 },
            success = { 66, 245, 90 }
        }
        local color = colors[aType] or colors.info

        while GetGameTimer() - startTime < duration do
            local progress = (GetGameTimer() - startTime) / duration
            local alpha = 255

            -- Fade in durante el primer 10%
            if progress < 0.1 then
                alpha = math.floor((progress / 0.1) * 255)
                -- Fade out durante el ltimo 20%
            elseif progress > 0.8 then
                alpha = math.floor(((1 - progress) / 0.2) * 255)
            end

            -- Fondo semi-transparente
            DrawRect(0.5, 0.12, 0.35, 0.08, 0, 0, 0, math.floor(alpha * 0.7))

            -- Borde superior coloreado
            DrawRect(0.5, 0.085, 0.35, 0.005, color[1], color[2], color[3], alpha)

            -- Ttulo (MS PEQUE'O)
            SetTextFont(4)
            SetTextScale(0.35, 0.35)
            SetTextColour(color[1], color[2], color[3], alpha)
            SetTextCentre(true)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName('Y" ANUNCIO DEL SERVIDOR')
            EndTextCommandDisplayText(0.5, 0.095)

            -- Mensaje (MS GRANDE)
            SetTextFont(4)
            SetTextScale(0.6, 0.6)
            SetTextColour(255, 255, 255, alpha)
            SetTextCentre(true)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(message)
            EndTextCommandDisplayText(0.5, 0.12)

            Wait(0)
        end
    end)
end)

RegisterNetEvent('lyxpanel:adminChat', function(name, message)
    TriggerEvent('chat:addMessage', {
        color = { 255, 140, 0 },
        multiline = true,
        args = { '[Admin Chat] ' .. name, message }
    })
end)

-- Mundo
RegisterNetEvent('lyxpanel:setWeather', function(weather)
    SetWeatherTypeNowPersist(weather)
end)

RegisterNetEvent('lyxpanel:setTime', function(hour, minute)
    NetworkOverrideClockTime(hour, minute, 0)
end)

-- Model
RegisterNetEvent('lyxpanel:changeModel', function(model)
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end
    SetPlayerModel(PlayerId(), hash)
    SetModelAsNoLongerNeeded(hash)
end)

-- ...............................................................................
-- NOCLIP THREAD (FIXED - SPACE para subir, CTRL para bajar)
-- ...............................................................................

CreateThread(function()
    while true do
        if noclipActive then
            local ped = PlayerPedId()
            local c = GetEntityCoords(ped)
            local camRot = GetGameplayCamRot(2)
            local speed = noclipSpeed

            -- Shift para ir ms rpido
            if IsControlPressed(0, 21) then speed = speed * 3 end

            -- Scroll para ajustar velocidad base
            if IsControlPressed(0, 241) then -- Scroll Up
                noclipSpeed = math.min(5.0, noclipSpeed + 0.1)
            end
            if IsControlPressed(0, 242) then -- Scroll Down
                noclipSpeed = math.max(0.1, noclipSpeed - 0.1)
            end

            local dir = { x = 0.0, y = 0.0, z = 0.0 }

            -- WASD para moverse horizontal
            if IsControlPressed(0, 32) then -- W
                dir.x = dir.x + math.sin(math.rad(-camRot.z)) * speed
                dir.y = dir.y + math.cos(math.rad(-camRot.z)) * speed
            end
            if IsControlPressed(0, 33) then -- S
                dir.x = dir.x - math.sin(math.rad(-camRot.z)) * speed
                dir.y = dir.y - math.cos(math.rad(-camRot.z)) * speed
            end
            if IsControlPressed(0, 34) then -- A (left)
                dir.x = dir.x - math.cos(math.rad(-camRot.z)) * speed
                dir.y = dir.y + math.sin(math.rad(-camRot.z)) * speed
            end
            if IsControlPressed(0, 35) then -- D (right)
                dir.x = dir.x + math.cos(math.rad(-camRot.z)) * speed
                dir.y = dir.y - math.sin(math.rad(-camRot.z)) * speed
            end

            -- SPACE para SUBIR, CTRL para BAJAR (Robust for Z-axis)
            if IsDisabledControlPressed(0, 22) then dir.z = dir.z + speed end -- SPACE
            if IsDisabledControlPressed(0, 36) then dir.z = dir.z - speed end -- CTRL

            -- Also Q/E
            if IsDisabledControlPressed(0, 44) then dir.z = dir.z + speed end -- Q
            if IsDisabledControlPressed(0, 38) then dir.z = dir.z - speed end -- E

            -- Reset velocity to prevent gravity fighting
            SetEntityVelocity(ped, 0.0, 0.0, 0.0)

            SetEntityCoordsNoOffset(ped, c.x + dir.x, c.y + dir.y, c.z + dir.z, true, true, true)
            SetEntityHeading(ped, -camRot.z)

            -- Desactivar controles de combate y movimiento que interfieren
            DisableControlAction(0, 24, true) -- Attack
            DisableControlAction(0, 25, true) -- Aim
            DisableControlAction(0, 47, true) -- Weapon
            DisableControlAction(0, 58, true) -- Weapon
            DisableControlAction(0, 22, true) -- JUMP (Evita saltar al subir)
            DisableControlAction(0, 36, true) -- DUCK (Evita agacharse al bajar)
            DisableControlAction(0, 21, true) -- SPRINT (Lo usamos para velocidad)
            DisableControlAction(0, 44, true) -- COVER (Q)
            DisableControlAction(0, 38, true) -- PICKUP (E)
        end
        Wait(0)
    end
end)


-- Key to open
if Config and Config.OpenKey and Config.OpenKey ~= '' then
    RegisterKeyMapping(Config.OpenCommand or 'lyxpanel', 'Abrir Panel Admin', 'keyboard', Config.OpenKey or 'F6')
end

-- Escape to close
CreateThread(function()
    while true do
        Wait(0)
        if isOpen and IsControlJustReleased(0, 200) then -- ESC
            SetNuiFocus(false, false)
            isOpen = false
            SendNUIMessage({ action = 'close' })
        end
    end
end)

-- ...............................................................................
-- STAFF STATUS BADGE (Visible sobre el jugador)
-- ...............................................................................

local staffStatusActive = false
local staffRole = "STAFF"

RegisterNUICallback('toggleStaffStatus', function(data, cb)
    if data and data.role then
        staffRole = data.role
    end

    staffStatusActive = (data and data.active == true) or false
    SendSecureServerEvent('lyxpanel:setStaffStatus', staffStatusActive, staffRole)
    cb({ active = staffStatusActive })
end)

-- Recibir lista de staff activos del servidor
local activeStaffPlayers = {}
local playerBlips = {}
local lastBlipUpdate = 0

RegisterNetEvent('lyxpanel:syncStaffStatus', function(staffList)
    activeStaffPlayers = staffList or {}
end)

local function RemoveAllPlayerBlips()
    for _, blip in pairs(playerBlips) do
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    playerBlips = {}
end

local function UpdatePlayerBlips()
    local stillExists = {}

    for _, player in ipairs(GetActivePlayers()) do
        local serverId = GetPlayerServerId(player)
        if serverId and serverId > 0 then
            stillExists[serverId] = true
            if serverId ~= GetPlayerServerId(PlayerId()) then
                local ped = GetPlayerPed(player)
                if ped and DoesEntityExist(ped) then
                    local blip = playerBlips[serverId]
                    if not blip or not DoesBlipExist(blip) then
                        blip = AddBlipForEntity(ped)
                        SetBlipSprite(blip, 1)
                        SetBlipColour(blip, 3)
                        SetBlipScale(blip, 0.85)
                        SetBlipAsShortRange(blip, false)
                        BeginTextCommandSetBlipName('STRING')
                        AddTextComponentString(('ID %d | %s'):format(serverId, GetPlayerName(player) or 'Player'))
                        EndTextCommandSetBlipName(blip)
                        playerBlips[serverId] = blip
                    else
                        SetBlipRotation(blip, math.ceil(GetEntityHeading(ped)))
                    end
                end
            end
        end
    end

    for serverId, blip in pairs(playerBlips) do
        if not stillExists[serverId] then
            if blip and DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
            playerBlips[serverId] = nil
        end
    end
end

local function DrawPlayerNametag(coords, label)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if onScreen then
        local camCoords = GetGameplayCamCoord()
        local dist = #(coords - camCoords)
        local scale = (1 / dist) * 2
        local fov = (1 / GetGameplayCamFov()) * 100
        scale = scale * fov

        if scale > 1.0 then scale = 1.0 end
        if scale < 0.35 then scale = 0.35 end

        SetTextScale(scale * 0.45, scale * 0.45)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 220)
        SetTextEntry("STRING")
        SetTextCentre(1)
        SetTextOutline()
        AddTextComponentString(label)
        DrawText(x, y)
    end
end

-- Dibujar badges de staff sobre los jugadores
CreateThread(function()
    while true do
        local sleep = 500

        if staffStatusActive and #activeStaffPlayers > 0 then
            sleep = 0
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)

            for _, staff in ipairs(activeStaffPlayers) do
                local targetPed = GetPlayerPed(GetPlayerFromServerId(staff.id))
                if targetPed and DoesEntityExist(targetPed) then
                    local targetCoords = GetEntityCoords(targetPed)
                    local dist = #(myCoords - targetCoords)

                    if dist < 50.0 then
                        -- Dibujar texto 3D sobre la cabeza
                        local headPos = GetPedBoneCoords(targetPed, 31086, 0.0, 0.0, 0.0) -- Head bone
                        headPos = vector3(headPos.x, headPos.y, headPos.z + 0.5)

                        DrawStaffBadge(headPos, staff.role or "STAFF", staff.name)
                    end
                end
            end

            local now = GetGameTimer()
            if (now - lastBlipUpdate) > 1000 then
                lastBlipUpdate = now
                UpdatePlayerBlips()
            end

            for _, player in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(player)
                if ped and DoesEntityExist(ped) and ped ~= myPed then
                    local coords = GetEntityCoords(ped)
                    local dist = #(myCoords - coords)
                    if dist < 25.0 then
                        local headPos = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
                        headPos = vector3(headPos.x, headPos.y, headPos.z + 0.6)
                        local sid = GetPlayerServerId(player)
                        DrawPlayerNametag(headPos, ('[%d] %s'):format(sid or 0, GetPlayerName(player) or 'Player'))
                    end
                end
            end
        else
            if next(playerBlips) ~= nil then
                RemoveAllPlayerBlips()
            end
        end

        Wait(sleep)
    end
end)

function DrawStaffBadge(coords, role, name)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if onScreen then
        local camCoords = GetGameplayCamCoord()
        local dist = #(coords - camCoords)
        local scale = (1 / dist) * 2
        local fov = (1 / GetGameplayCamFov()) * 100
        scale = scale * fov

        -- Escala grande
        if scale > 1.0 then scale = 1.0 end
        if scale < 0.4 then scale = 0.4 end

        -- SOLO TEXTO - Sin fondo
        SetTextScale(scale * 0.6, scale * 0.6)
        SetTextFont(4)                  -- Pricedown (fuente grande de GTA)
        SetTextProportional(1)
        SetTextColour(255, 50, 50, 255) -- Rojo brillante
        SetTextEntry("STRING")
        SetTextCentre(1)
        SetTextOutline()
        SetTextDropshadow(3, 0, 0, 0, 255) -- Sombra para legibilidad
        AddTextComponentString("~. " .. string.upper(role or "STAFF"))
        DrawText(x, y)
    end
end

-- ...............................................................................
-- EVENTOS DE TROLLEO
-- ...............................................................................

-- Explosin visual sin dao
RegisterNetEvent('lyxpanel:troll:explode', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    AddExplosion(coords.x, coords.y, coords.z, 7, 0.0, true, false, 0.0)
    ShakeGameplayCam('MEDIUM_EXPLOSION_SHAKE', 1.0)
end)

-- Prender fuego
RegisterNetEvent('lyxpanel:troll:fire', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    StartScriptFire(coords.x, coords.y, coords.z, 25, true)
    Citizen.Wait(5000)
    local fires = GetNumberOfFiresInRange(coords.x, coords.y, coords.z, 10.0)
    StopFireInRange(coords.x, coords.y, coords.z, 10.0)
end)

-- Lanzar al aire
RegisterNetEvent('lyxpanel:troll:launch:legacy', function()
    local ped = PlayerPedId()
    SetEntityVelocity(ped, 0.0, 0.0, 50.0)
    SetPedToRagdoll(ped, 5000, 5000, 0, false, false, false)
end)

-- Ragdoll
RegisterNetEvent('lyxpanel:troll:ragdoll', function()
    local ped = PlayerPedId()
    SetPedToRagdoll(ped, 5000, 5000, 0, false, false, false)
end)

-- Efecto borracho
RegisterNetEvent('lyxpanel:troll:drunk', function(duration)
    duration = duration or 30
    local ped = PlayerPedId()
    RequestAnimSet("move_m@drunk@verydrunk")
    while not HasAnimSetLoaded("move_m@drunk@verydrunk") do
        Wait(10)
    end
    SetPedMovementClipset(ped, "move_m@drunk@verydrunk", 0.5)
    SetPedIsDrunk(ped, true)

    CreateThread(function()
        local endTime = GetGameTimer() + (duration * 1000)
        while GetGameTimer() < endTime do
            ShakeGameplayCam('DRUNK_SHAKE', 2.0)
            Wait(500)
        end
        ResetPedMovementClipset(ped, 0.0)
        SetPedIsDrunk(ped, false)
        StopGameplayCamShaking(true)
    end)
end)

-- Pantalla de drogas
RegisterNetEvent('lyxpanel:troll:drugScreen', function(duration)
    duration = duration or 20
    AnimpostfxPlay("DrugsMichaelAliensFightIn", 0, true)
    SetTimecycleModifier("spectator5")

    CreateThread(function()
        Wait(duration * 1000)
        AnimpostfxStop("DrugsMichaelAliensFightIn")
        ClearTimecycleModifier()
    end)
end)

-- Pantalla negra
RegisterNetEvent('lyxpanel:troll:blackScreen', function(duration)
    duration = duration or 10
    DoScreenFadeOut(500)

    CreateThread(function()
        Wait(duration * 1000)
        DoScreenFadeIn(500)
    end)
end)

-- Sonido de susto
RegisterNetEvent('lyxpanel:troll:scream', function()
    PlaySoundFrontend(-1, "PAIN_HIGH", "PLAYER_PAIN_SOUNDS", true)
    ShakeGameplayCam('HAND_SHAKE', 2.0)
    Wait(100)
    PlaySoundFrontend(-1, "MP_CABLE_SIZZLE", "HUD_FRONTEND_WEAPONS_PICKUPS_SOUNDSET", true)
end)

-- Teleport (usado por randomTeleport)
RegisterNetEvent('lyxpanel:troll:teleport', function(x, y, z)
    SetEntityCoords(PlayerPedId(), x, y, z, false, false, false, false)
end)

-- Quitar ropa
RegisterNetEvent('lyxpanel:troll:strip', function()
    local ped = PlayerPedId()

    -- Componentes bsicos que se pueden "quitar"
    for i = 3, 11 do
        SetPedComponentVariation(ped, i, 0, 0, 0)
    end
end)

-- Invertir controles (reimplementado correctamente)
local invertedControls = false

RegisterNetEvent('lyxpanel:troll:invert', function(duration)
    duration = duration or 15
    invertedControls = true

    -- Notificar al jugador que algo est mal
    CreateThread(function()
        Wait(2000)
        if invertedControls then
            -- Confusing screen effects
            SetTimecycleModifier("damage")
            SetTimecycleModifierStrength(0.3)
        end
    end)

    CreateThread(function()
        local endTime = GetGameTimer() + (duration * 1000)

        while GetGameTimer() < endTime and invertedControls do
            Wait(0)
            local ped = PlayerPedId()

            -- Disable normal controls
            DisableControlAction(0, 32, true) -- W
            DisableControlAction(0, 33, true) -- S
            DisableControlAction(0, 34, true) -- A
            DisableControlAction(0, 35, true) -- D

            -- Check inverted inputs and apply
            if IsDisabledControlPressed(0, 32) then -- Pressing W - go backwards
                local coords = GetEntityCoords(ped)
                local fwd = GetEntityForwardVector(ped)
                local targetX, targetY, targetZ = coords.x - fwd.x * 2.0, coords.y - fwd.y * 2.0, coords.z
                TaskGoStraightToCoord(ped, targetX, targetY, targetZ, 1.0, -1, 0.0, 0.0)
            end
            if IsDisabledControlPressed(0, 33) then -- Pressing S - go forwards
                local coords = GetEntityCoords(ped)
                local fwd = GetEntityForwardVector(ped)
                local targetX, targetY, targetZ = coords.x + fwd.x * 2.0, coords.y + fwd.y * 2.0, coords.z
                TaskGoStraightToCoord(ped, targetX, targetY, targetZ, 1.0, -1, 0.0, 0.0)
            end
            if IsDisabledControlPressed(0, 34) then -- Pressing A
                local heading = GetEntityHeading(ped)
                SetEntityHeading(ped, heading - 3.0)
            end
            if IsDisabledControlPressed(0, 35) then -- Pressing D
                local heading = GetEntityHeading(ped)
                SetEntityHeading(ped, heading + 3.0)
            end
        end

        invertedControls = false
        ClearTimecycleModifier()
    end)
end)

-- Cambiar modelo a ped aleatorio o especfico (FIXED for animals)
RegisterNetEvent('lyxpanel:troll:randomPed', function(model)
    print('[LyxPanel] Changing model to:', model)
    local hash = GetHashKey(model)

    -- Request the model
    RequestModel(hash)

    -- Wait for model to load (up to 10 seconds for large models)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 100 do
        Wait(100)
        timeout = timeout + 1
    end

    if HasModelLoaded(hash) then
        print('[LyxPanel] Model loaded, applying...')
        SetPlayerModel(PlayerId(), hash)
        SetModelAsNoLongerNeeded(hash)

        -- For animals, need to refresh ped after model change
        Wait(100)
        local newPed = PlayerPedId()
        SetPedDefaultComponentVariation(newPed)
    else
        print('[LyxPanel] ERROR: Failed to load model:', model)
    end
end)

-- Hacer bailar
RegisterNetEvent('lyxpanel:troll:dance', function()
    local ped = PlayerPedId()
    local dances = {
        { dict = "anim@mp_player_intcelebrationmale@chicken_taunt", anim = "chicken_taunt" },
        { dict = "anim@mp_player_intcelebrationfemale@wave",        anim = "wave" },
        { dict = "rcmfanatic3",                                     anim = "fab_dance" },
        { dict = "missfbi3_sniping",                                anim = "dance_m_default" }
    }

    local dance = dances[math.random(#dances)]
    RequestAnimDict(dance.dict)
    local timeout = 0
    while not HasAnimDictLoaded(dance.dict) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end

    if HasAnimDictLoaded(dance.dict) then
        TaskPlayAnim(ped, dance.dict, dance.anim, 8.0, -8.0, 10000, 1, 0, false, false, false)
    end
end)

-- ...............................................................................
-- NUEVOS TROLLS AVANZADOS
-- ...............................................................................

-- Invisible (solo para l - otros lo ven)
RegisterNetEvent('lyxpanel:troll:invisible', function(duration)
    duration = duration or 30
    local ped = PlayerPedId()

    -- Hacer invisible solo localmente
    SetEntityVisible(ped, false, false)
    SetEntityAlpha(ped, 0, false)

    CreateThread(function()
        Wait(duration * 1000)
        local ped2 = PlayerPedId()
        SetEntityVisible(ped2, true, false)
        SetEntityAlpha(ped2, 255, false)
    end)
end)

-- Spin (girar sin control)
RegisterNetEvent('lyxpanel:troll:spin', function(duration)
    duration = duration or 15
    local endTime = GetGameTimer() + (duration * 1000)

    CreateThread(function()
        while GetGameTimer() < endTime do
            local ped = PlayerPedId()
            local heading = GetEntityHeading(ped)
            SetEntityHeading(ped, heading + 15.0)
            Wait(50)
        end
    end)
end)

-- Shrink (hacer enano)
RegisterNetEvent('lyxpanel:troll:shrink', function(duration)
    duration = duration or 60
    local ped = PlayerPedId()

    -- Aplicar escala pequea
    SetPedComponentVariation(ped, 0, 0, 0, 0)
    SetEntityVisible(ped, false, false)
    Wait(50)
    SetEntityVisible(ped, true, false)

    -- Forzar animacin agachado
    RequestAnimSet("move_ped_crouched")
    while not HasAnimSetLoaded("move_ped_crouched") do Wait(10) end
    SetPedMovementClipset(ped, "move_ped_crouched", 1.0)

    -- Efecto visual de encogimiento
    CreateThread(function()
        local endTime = GetGameTimer() + (duration * 1000)
        while GetGameTimer() < endTime do
            local p = PlayerPedId()
            -- Mantener agachado forzosamente
            DisableControlAction(0, 36, true) -- CTRL
            if not IsPedDucking(p) then
                SetPedDucking(p, true)
            end
            Wait(0)
        end

        -- Restaurar
        ResetPedMovementClipset(PlayerPedId(), 0.0)
        SetPedDucking(PlayerPedId(), false)
    end)
end)

-- Giant (hacer gigante - efecto visual)
RegisterNetEvent('lyxpanel:troll:giant', function(duration)
    duration = duration or 30
    local ped = PlayerPedId()

    -- Forzar caminar muy lento como gigante
    RequestAnimSet("move_m@drunk@verydrunk")
    while not HasAnimSetLoaded("move_m@drunk@verydrunk") do Wait(10) end
    SetPedMovementClipset(ped, "move_m@drunk@verydrunk", 0.3)

    -- Shake screen para simular pisadas
    CreateThread(function()
        local endTime = GetGameTimer() + (duration * 1000)
        while GetGameTimer() < endTime do
            ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", 0.1)
            Wait(800)
        end
        ResetPedMovementClipset(PlayerPedId(), 0.0)
    end)
end)

-- Clone Army (spawnar clones que atacan)
RegisterNetEvent('lyxpanel:troll:clones', function(count)
    count = count or 5
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local model = GetEntityModel(ped)

    for i = 1, count do
        CreateThread(function()
            RequestModel(model)
            while not HasModelLoaded(model) do Wait(10) end

            local angle = (360 / count) * i
            local rad = math.rad(angle)
            local x = coords.x + math.cos(rad) * 3.0
            local y = coords.y + math.sin(rad) * 3.0

            local clone = CreatePed(4, model, x, y, coords.z, GetEntityHeading(ped), true, false)
            SetPedFleeAttributes(clone, 0, false)
            SetPedCombatAttributes(clone, 46, true)
            TaskCombatPed(clone, ped, 0, 16)

            -- Auto-eliminar despus de 30 segundos
            Wait(30000)
            if DoesEntityExist(clone) then
                DeleteEntity(clone)
            end
        end)
    end
end)

-- Launch (lanzar al aire)
RegisterNetEvent('lyxpanel:troll:launch', function(force)
    force = force or 50.0
    local ped = PlayerPedId()

    SetEntityVelocity(ped, 0.0, 0.0, force)
    SetPedToRagdoll(ped, 5000, 5000, 0, true, true, false)
end)

-- ...............................................................................
-- COMANDOS DIRECTOS (FIXED)
-- ...............................................................................

-- /tpm - Teleport to Marker (FIXED)
RegisterNetEvent('lyxpanel:tpm', function()
    local blip = GetFirstBlipInfoId(8) -- Waypoint blip
    if not DoesBlipExist(blip) then
        SetNotificationTextEntry('STRING')
        AddTextComponentString('~r~No hay marcador en el mapa')
        DrawNotification(true, true)
        return
    end

    local coords = GetBlipInfoIdCoord(blip)
    local ped = PlayerPedId()

    -- Encontrar Z correcto
    local groundFound = false
    local groundZ = 0.0

    for height = 1000.0, 0.0, -25.0 do
        SetEntityCoordsNoOffset(ped, coords.x, coords.y, height, false, false, false)
        Wait(50)
        local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, height, true)
        if found then
            groundZ = z
            groundFound = true
            break
        end
    end

    if groundFound then
        SetEntityCoords(ped, coords.x, coords.y, groundZ + 1.0, false, false, false, false)
    else
        SetEntityCoords(ped, coords.x, coords.y, coords.z + 100.0, false, false, false, false)
    end

    SetNotificationTextEntry('STRING')
    AddTextComponentString('~g~Teleportado al marcador')
    DrawNotification(true, true)
end)

-- Teleport directo a coordenadas
RegisterNetEvent('lyxpanel:teleportTo', function(x, y, z)
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, x, y, z + 1.0, false, false, false, false)
end)

-- Reparar vehculo
RegisterNetEvent('lyxpanel:repairVehicle', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        -- Buscar vehculo cercano
        vehicle = GetVehiclePedIsTryingToEnter(ped)
        if vehicle == 0 then
            local coords = GetEntityCoords(ped)
            vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
        end
    end

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehicleDirtLevel(vehicle, 0.0)

        SetNotificationTextEntry('STRING')
        AddTextComponentString('~g~Vehculo reparado')
        DrawNotification(true, true)
    else
        SetNotificationTextEntry('STRING')
        AddTextComponentString('~r~No hay vehculo cercano')
        DrawNotification(true, true)
    end
end)

-- Sonido de notificacin
RegisterNetEvent('lyxpanel:playSound', function(soundType)
    if soundType == 'report' then
        PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
    elseif soundType == 'alert' then
        PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    elseif soundType == 'success' then
        PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end
end)

-- Anuncio global
RegisterNetEvent('lyxpanel:announce:legacy', function(message, msgType, adminName)
    -- Mostrar anuncio grande
    SetNotificationTextEntry('STRING')
    AddTextComponentString('Y" [' .. (adminName or 'Admin') .. '] ' .. message)
    DrawNotification(true, true)

    -- Tambin en chat
    TriggerEvent('chat:addMessage', {
        color = { 255, 200, 0 },
        multiline = true,
        args = { 'Y" ANUNCIO', message }
    })

    -- Sonido
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
end)

-- Notificacin mejorada
RegisterNetEvent('lyxpanel:notify', function(msgType, message)
    local prefix = ''
    if msgType == 'success' then
        prefix = '~g~o. '
    elseif msgType == 'error' then
        prefix = '~r~O '
    elseif msgType == 'warning' then
        prefix = '~y~s '
    elseif msgType == 'info' then
        prefix = '~b~" '
    end

    SetNotificationTextEntry('STRING')
    AddTextComponentString(prefix .. (message or ''))
    DrawNotification(true, true)
end)

-- ...............................................................................
-- v4.2 - NEW CLIENT EVENT HANDLERS
-- ...............................................................................

-- Clear Area - Delete nearby vehicles in radius
RegisterNetEvent('lyxpanel:clearArea', function(radius)
    radius = radius or 100
    local playerCoords = GetEntityCoords(PlayerPedId())
    local count = 0

    -- Delete vehicles
    local handle, vehicle = FindFirstVehicle()
    local success = true

    while success do
        if DoesEntityExist(vehicle) then
            local vehCoords = GetEntityCoords(vehicle)
            if #(playerCoords - vehCoords) <= radius then
                if not IsPedInVehicle(PlayerPedId(), vehicle, false) then
                    DeleteEntity(vehicle)
                    count = count + 1
                end
            end
        end
        success, vehicle = FindNextVehicle(handle)
    end
    EndFindVehicle(handle)

    print('[LyxPanel] Cleared ' .. count .. ' vehicles in radius ' .. radius)
end)

-- Reset Ped to default
RegisterNetEvent('lyxpanel:resetPed', function()
    local playerPed = PlayerPedId()
    local model = GetHashKey('mp_m_freemode_01')

    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    SetPlayerModel(PlayerId(), model)
    SetModelAsNoLongerNeeded(model)
end)

-- Admin Jail Timer
local jailActive = false
local jailEndTime = 0

RegisterNetEvent('lyxpanel:startJail', function(duration)
    jailActive = true
    jailEndTime = GetGameTimer() + (duration * 1000)

    CreateThread(function()
        while jailActive and GetGameTimer() < jailEndTime do
            -- Prevent leaving jail area
            local playerCoords = GetEntityCoords(PlayerPedId())
            local jailCoords = vector3(1641.6, 2571.0, 44.5)

            if #(playerCoords - jailCoords) > 50.0 then
                SetEntityCoords(PlayerPedId(), jailCoords.x, jailCoords.y, jailCoords.z)
            end

            -- Show remaining time
            local remaining = math.floor((jailEndTime - GetGameTimer()) / 1000)
            DrawText3D(jailCoords.x, jailCoords.y, jailCoords.z + 1.0,
                '~r~ADMIN JAIL~w~\n' .. remaining .. 's restantes')

            Wait(0)
        end

        jailActive = false
        TriggerEvent('chat:addMessage', {
            color = { 0, 255, 0 },
            args = { 'o. JAIL', 'Has sido liberado de Admin Jail' }
        })
    end)
end)

function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

print('^2[LyxPanel v4.2]^7 Client loaded (with v4.2 Features)')



