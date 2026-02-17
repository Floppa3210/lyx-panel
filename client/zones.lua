--[[
    LyxPanel v4.3 - ELITE ZONE & WARP SYSTEM

    Features:
    - Zone cleanup (vehicles, peds, objects in radius)
    - Saved warp locations (personal warps)
    - Spectate nearest player
    - Area scan (show entities in radius)
]]

local SavedWarps = {}
local WarpFile = 'lyxpanel_warps.json'

-- ═══════════════════════════════════════════════════════════════════════════════
-- ZONE CLEANUP
-- ═══════════════════════════════════════════════════════════════════════════════

local function CleanupZone(radius, options)
    options = options or {}
    local playerCoords = GetEntityCoords(PlayerPedId())
    local stats = {
        vehicles = 0,
        peds = 0,
        objects = 0
    }

    -- Delete vehicles
    if options.vehicles ~= false then
        local handle, vehicle = FindFirstVehicle()
        local success = true
        while success do
            if DoesEntityExist(vehicle) then
                local vehCoords = GetEntityCoords(vehicle)
                if #(playerCoords - vehCoords) <= radius then
                    -- Don't delete vehicle player is in
                    if not IsPedInVehicle(PlayerPedId(), vehicle, false) then
                        -- Don't delete mission vehicles
                        if not IsEntityAMissionEntity(vehicle) or options.includeMission then
                            SetEntityAsMissionEntity(vehicle, true, true)
                            DeleteEntity(vehicle)
                            stats.vehicles = stats.vehicles + 1
                        end
                    end
                end
            end
            success, vehicle = FindNextVehicle(handle)
        end
        EndFindVehicle(handle)
    end

    -- Delete peds (NPCs only)
    if options.peds then
        local handle, ped = FindFirstPed()
        local success = true
        while success do
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                local pedCoords = GetEntityCoords(ped)
                if #(playerCoords - pedCoords) <= radius then
                    SetEntityAsMissionEntity(ped, true, true)
                    DeleteEntity(ped)
                    stats.peds = stats.peds + 1
                end
            end
            success, ped = FindNextPed(handle)
        end
        EndFindPed(handle)
    end

    -- Delete objects
    if options.objects then
        local handle, object = FindFirstObject()
        local success = true
        while success do
            if DoesEntityExist(object) then
                local objCoords = GetEntityCoords(object)
                if #(playerCoords - objCoords) <= radius then
                    SetEntityAsMissionEntity(object, true, true)
                    DeleteEntity(object)
                    stats.objects = stats.objects + 1
                end
            end
            success, object = FindNextObject(handle)
        end
        EndFindObject(handle)
    end

    return stats
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- SAVED WARPS (Client-side storage with KVP)
-- ═══════════════════════════════════════════════════════════════════════════════

local function LoadWarps()
    local data = GetResourceKvpString('lyxpanel_warps')
    if data then
        SavedWarps = json.decode(data) or {}
    end
end

local function SaveWarpsToKVP()
    SetResourceKvp('lyxpanel_warps', json.encode(SavedWarps))
end

local function AddWarp(name)
    local coords = GetEntityCoords(PlayerPedId())
    local heading = GetEntityHeading(PlayerPedId())

    SavedWarps[name:lower()] = {
        name = name,
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = heading,
        timestamp = os.time()
    }

    SaveWarpsToKVP()
    return true
end

local function DeleteWarp(name)
    if SavedWarps[name:lower()] then
        SavedWarps[name:lower()] = nil
        SaveWarpsToKVP()
        return true
    end
    return false
end

local function TeleportToWarp(name)
    local warp = SavedWarps[name:lower()]
    if warp then
        SetPedCoordsKeepVehicle(PlayerPedId(), warp.x, warp.y, warp.z)
        SetEntityHeading(PlayerPedId(), warp.heading)
        return true
    end
    return false
end

local function GetAllWarps()
    local list = {}
    for _, warp in pairs(SavedWarps) do
        table.insert(list, warp)
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- SPECTATE NEAREST PLAYER
-- ═══════════════════════════════════════════════════════════════════════════════

local function GetNearestPlayer()
    local myCoords = GetEntityCoords(PlayerPedId())
    local closestDistance = 999999
    local closestPlayer = nil

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local targetPed = GetPlayerPed(playerId)
            if DoesEntityExist(targetPed) then
                local targetCoords = GetEntityCoords(targetPed)
                local distance = #(myCoords - targetCoords)
                if distance < closestDistance then
                    closestDistance = distance
                    closestPlayer = playerId
                end
            end
        end
    end

    return closestPlayer, closestDistance
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- AREA SCAN (Entity counter)
-- ═══════════════════════════════════════════════════════════════════════════════

local function ScanArea(radius)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local stats = {
        vehicles = 0,
        peds = 0,
        players = 0,
        objects = 0
    }

    -- Count vehicles
    local handle, vehicle = FindFirstVehicle()
    local success = true
    while success do
        if DoesEntityExist(vehicle) then
            local vehCoords = GetEntityCoords(vehicle)
            if #(playerCoords - vehCoords) <= radius then
                stats.vehicles = stats.vehicles + 1
            end
        end
        success, vehicle = FindNextVehicle(handle)
    end
    EndFindVehicle(handle)

    -- Count peds
    local handle2, ped = FindFirstPed()
    success = true
    while success do
        if DoesEntityExist(ped) then
            local pedCoords = GetEntityCoords(ped)
            if #(playerCoords - pedCoords) <= radius then
                if IsPedAPlayer(ped) then
                    stats.players = stats.players + 1
                else
                    stats.peds = stats.peds + 1
                end
            end
        end
        success, ped = FindNextPed(handle2)
    end
    EndFindPed(handle2)

    return stats
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNUICallback('cleanupZone', function(data, cb)
    if not IsNuiFocused() then
        cb({ success = false, error = 'panel_not_focused' })
        return
    end
    local radius = data.radius or 100
    local stats = CleanupZone(radius, {
        vehicles = data.vehicles ~= false,
        peds = data.peds == true,
        objects = data.objects == true
    })
    cb(stats)
end)

RegisterNUICallback('addWarp', function(data, cb)
    if not IsNuiFocused() then
        cb({ success = false, error = 'panel_not_focused' })
        return
    end
    local success = AddWarp(data.name)
    cb({ success = success })
end)

RegisterNUICallback('deleteWarp', function(data, cb)
    if not IsNuiFocused() then
        cb({ success = false, error = 'panel_not_focused' })
        return
    end
    local success = DeleteWarp(data.name)
    cb({ success = success })
end)

RegisterNUICallback('teleportToWarp', function(data, cb)
    if not IsNuiFocused() then
        cb({ success = false, error = 'panel_not_focused' })
        return
    end
    local success = TeleportToWarp(data.name)
    cb({ success = success })
end)

RegisterNUICallback('getWarps', function(data, cb)
    if not IsNuiFocused() then
        cb({})
        return
    end
    cb(GetAllWarps())
end)

RegisterNUICallback('spectateNearest', function(data, cb)
    if not IsNuiFocused() then
        cb({ success = false, error = 'panel_not_focused' })
        return
    end
    local nearest, distance = GetNearestPlayer()
    if nearest then
        TriggerEvent('lyxpanel:startSpectate', GetPlayerServerId(nearest))
        cb({ success = true, distance = distance })
    else
        cb({ success = false })
    end
end)

RegisterNUICallback('scanArea', function(data, cb)
    if not IsNuiFocused() then
        cb({ success = false, error = 'panel_not_focused' })
        return
    end
    local stats = ScanArea(data.radius or 100)
    cb(stats)
end)

-- Load warps on start
CreateThread(function()
    Wait(1000)
    LoadWarps()
    print('^2[LyxPanel v4.3]^7 Zone & Warp system loaded (' .. #GetAllWarps() .. ' warps)')
end)

-- Exports
exports('CleanupZone', CleanupZone)
exports('AddWarp', AddWarp)
exports('DeleteWarp', DeleteWarp)
exports('TeleportToWarp', TeleportToWarp)
exports('GetAllWarps', GetAllWarps)
exports('ScanArea', ScanArea)
