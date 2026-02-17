--[[
    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                    LYXPANEL v4.5 - CLIENT FEATURES                           ║
    ║                      Advanced Client-Side Features                            ║
    ╠═══════════════════════════════════════════════════════════════════════════════╣
    ║  Features: Vehicle Control, HUD, Outfits, Fuel Integration, etc.             ║
    ╚═══════════════════════════════════════════════════════════════════════════════╝
]]

local function _TriggerPanelEvent(eventName, ...)
    if type(LyxPanelSecureTrigger) == 'function' then
        return LyxPanelSecureTrigger(eventName, ...)
    end
    return TriggerServerEvent(eventName, ...)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- VEHICLE ADVANCED CONTROLS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Bring vehicle to location
RegisterNetEvent('lyxpanel:bringVehicle', function(x, y, z)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle ~= 0 then
        SetEntityCoords(vehicle, x, y, z, false, false, false, true)
    end
end)

-- Toggle vehicle doors
RegisterNetEvent('lyxpanel:toggleVehicleDoors', function(doorIndex)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle == 0 then
        -- Get nearby vehicle
        vehicle = GetClosestVehicle(GetEntityCoords(ped), 10.0, 0, 71)
    end
    
    if vehicle ~= 0 then
        if doorIndex == -1 then
            -- Toggle all doors
            for i = 0, 5 do
                local angle = GetVehicleDoorAngleRatio(vehicle, i)
                if angle > 0.0 then
                    SetVehicleDoorShut(vehicle, i, false)
                else
                    SetVehicleDoorOpen(vehicle, i, false, false)
                end
            end
        else
            local angle = GetVehicleDoorAngleRatio(vehicle, doorIndex)
            if angle > 0.0 then
                SetVehicleDoorShut(vehicle, doorIndex, false)
            else
                SetVehicleDoorOpen(vehicle, doorIndex, false, false)
            end
        end
    end
end)

-- Toggle vehicle engine
RegisterNetEvent('lyxpanel:toggleVehicleEngine', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle ~= 0 then
        local engineOn = GetIsVehicleEngineRunning(vehicle)
        SetVehicleEngineOn(vehicle, not engineOn, false, true)
    end
end)

-- Set vehicle fuel
RegisterNetEvent('lyxpanel:setVehicleFuel', function(fuelLevel)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle ~= 0 then
        -- Try different fuel scripts
        local fuelConfig = Config.FuelScript or {}
        
        if fuelConfig.resource == 'LegacyFuel' then
            exports['LegacyFuel']:SetFuel(vehicle, fuelLevel)
        elseif fuelConfig.resource == 'ox_fuel' then
            Entity(vehicle).state.fuel = fuelLevel
        elseif fuelConfig.resource == 'cdn-fuel' then
            exports['cdn-fuel']:SetFuel(vehicle, fuelLevel)
        elseif fuelConfig.resource == 'ps-fuel' then
            exports['ps-fuel']:SetFuel(vehicle, fuelLevel)
        else
            -- Native fallback
            SetVehicleFuelLevel(vehicle, fuelLevel + 0.0)
            DecorSetFloat(vehicle, '_FUEL_LEVEL', fuelLevel + 0.0)
        end
    end
end)

RegisterNetEvent('lyxpanel:freezeVehicle', function(enabled)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end
    FreezeEntityPosition(vehicle, enabled == true)
end)

RegisterNetEvent('lyxpanel:setVehicleLivery', function(livery)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    livery = tonumber(livery) or -1
    if livery >= 0 then
        local max = GetVehicleLiveryCount(vehicle) or 0
        if max > 0 then
            if livery >= max then livery = max - 1 end
            SetVehicleLivery(vehicle, livery)
        end
    else
        -- Reset-ish behavior: default livery index 0 when supported.
        local max = GetVehicleLiveryCount(vehicle) or 0
        if max > 0 then
            SetVehicleLivery(vehicle, 0)
        end
    end
end)

RegisterNetEvent('lyxpanel:setVehicleExtra', function(extraId, enabled)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    extraId = tonumber(extraId) or 0
    if extraId < 0 or extraId > 20 then return end
    enabled = (enabled == true)

    if DoesExtraExist(vehicle, extraId) then
        -- Native expects: disable = 1, enable = 0
        SetVehicleExtra(vehicle, extraId, enabled and 0 or 1)
    end
end)

RegisterNetEvent('lyxpanel:setVehicleNeon', function(enabled, color)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    enabled = (enabled == true)
    local r, g, b = 255, 0, 0
    if type(color) == 'table' then
        r = math.max(0, math.min(255, tonumber(color.r) or r))
        g = math.max(0, math.min(255, tonumber(color.g) or g))
        b = math.max(0, math.min(255, tonumber(color.b) or b))
    end

    SetVehicleNeonLightsColour(vehicle, r, g, b)
    for i = 0, 3 do
        SetVehicleNeonLightEnabled(vehicle, i, enabled)
    end
end)

RegisterNetEvent('lyxpanel:setVehicleWheelSmoke', function(color)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    local r, g, b = 255, 255, 255
    if type(color) == 'table' then
        r = math.max(0, math.min(255, tonumber(color.r) or r))
        g = math.max(0, math.min(255, tonumber(color.g) or g))
        b = math.max(0, math.min(255, tonumber(color.b) or b))
    end

    ToggleVehicleMod(vehicle, 20, true) -- Tyre smoke
    SetVehicleTyreSmokeColor(vehicle, r, g, b)
end)

RegisterNetEvent('lyxpanel:setVehiclePaintAdvanced', function(pearlescent, wheelColor)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    pearlescent = math.max(0, math.min(160, tonumber(pearlescent) or 0))
    wheelColor = math.max(0, math.min(160, tonumber(wheelColor) or 0))
    SetVehicleExtraColours(vehicle, pearlescent, wheelColor)
end)

RegisterNetEvent('lyxpanel:setVehicleXenon', function(enabled, colorIndex)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    enabled = (enabled == true)
    colorIndex = math.floor(tonumber(colorIndex) or -1)
    if colorIndex < -1 then colorIndex = -1 end
    if colorIndex > 13 then colorIndex = 13 end

    ToggleVehicleMod(vehicle, 22, enabled)
    if enabled then
        SetVehicleXenonLightsColor(vehicle, colorIndex)
    end
end)

RegisterNetEvent('lyxpanel:setVehicleModkit', function(mods)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or type(mods) ~= 'table' then return end

    SetVehicleModKit(vehicle, 0)

    local function applyMod(modType, level)
        level = math.floor(tonumber(level) or -1)
        if level < 0 then return end

        local maxMods = GetNumVehicleMods(vehicle, modType) or 0
        if maxMods <= 0 then return end
        if level >= maxMods then level = maxMods - 1 end
        SetVehicleMod(vehicle, modType, level, false)
    end

    applyMod(11, mods.engine)
    applyMod(12, mods.brakes)
    applyMod(13, mods.transmission)
    applyMod(15, mods.suspension)
    applyMod(16, mods.armor)
    ToggleVehicleMod(vehicle, 18, mods.turbo == true)
end)

-- Warp into vehicle
RegisterNetEvent('lyxpanel:warpIntoVehicle', function(driverPlayerId)
    local ped = PlayerPedId()
    local targetPed = GetPlayerPed(GetPlayerFromServerId(driverPlayerId))
    local vehicle = GetVehiclePedIsIn(targetPed, false)
    
    if vehicle ~= 0 then
        local freeSeat = -1
        for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
            if IsVehicleSeatFree(vehicle, i) then
                freeSeat = i
                break
            end
        end
        
        if freeSeat ~= -1 then
            TaskWarpPedIntoVehicle(ped, vehicle, freeSeat)
        end
    end
end)

-- Warp out of vehicle
RegisterNetEvent('lyxpanel:warpOutOfVehicle', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle ~= 0 then
        TaskLeaveVehicle(ped, vehicle, 16)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- SELF ADMIN HUD
-- ═══════════════════════════════════════════════════════════════════════════════

local hudEnabled = false
local hudData = {
    fps = 0,
    speed = 0,
    entityCount = 0,
    coords = { x = 0, y = 0, z = 0 }
}

local function GetNearbyEntityCount()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local count = 0
    
    -- Vehicles
    local vehicles = GetGamePool('CVehicle')
    for _, v in ipairs(vehicles) do
        if #(GetEntityCoords(v) - coords) < 100.0 then
            count = count + 1
        end
    end
    
    -- Peds
    local peds = GetGamePool('CPed')
    for _, p in ipairs(peds) do
        if #(GetEntityCoords(p) - coords) < 100.0 then
            count = count + 1
        end
    end
    
    return count
end

-- HUD Thread
CreateThread(function()
    local lastTime = GetGameTimer()
    local frameCount = 0
    
    while true do
        Wait(0)
        
        if hudEnabled and Config.SelfAdminHud and Config.SelfAdminHud.enabled then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            
            -- Update data every 500ms
            frameCount = frameCount + 1
            if GetGameTimer() - lastTime >= 500 then
                hudData.fps = math.floor(frameCount * 2)
                frameCount = 0
                lastTime = GetGameTimer()
                
                -- Speed
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle ~= 0 then
                    hudData.speed = math.floor(GetEntitySpeed(vehicle) * 3.6) -- km/h
                else
                    hudData.speed = 0
                end
                
                -- Entity count
                if Config.SelfAdminHud.showEntityCount then
                    hudData.entityCount = GetNearbyEntityCount()
                end
            end
            
            hudData.coords = { x = coords.x, y = coords.y, z = coords.z }
            
            -- Draw HUD
            local position = Config.SelfAdminHud.position or 'bottom-right'
            local baseX, baseY = 0.85, 0.85
            
            if position == 'top-left' then baseX, baseY = 0.01, 0.01
            elseif position == 'top-right' then baseX, baseY = 0.85, 0.01
            elseif position == 'bottom-left' then baseX, baseY = 0.01, 0.85
            end
            
            local y = baseY
            local lineHeight = 0.025
            
            -- FPS
            if Config.SelfAdminHud.showFPS then
                DrawAdminText(baseX, y, string.format('FPS: %d', hudData.fps))
                y = y + lineHeight
            end
            
            -- Speed
            if Config.SelfAdminHud.showSpeedometer and hudData.speed > 0 then
                DrawAdminText(baseX, y, string.format('Speed: %d km/h', hudData.speed))
                y = y + lineHeight
            end
            
            -- Entity count
            if Config.SelfAdminHud.showEntityCount then
                DrawAdminText(baseX, y, string.format('Entities: %d', hudData.entityCount))
                y = y + lineHeight
            end
            
            -- Coords in noclip
            if Config.SelfAdminHud.showCoordsInNoclip and noclipActive then
                DrawAdminText(baseX, y, string.format('X: %.1f Y: %.1f Z: %.1f', 
                    hudData.coords.x, hudData.coords.y, hudData.coords.z))
            end
        else
            Wait(500)
        end
    end
end)

function DrawAdminText(x, y, text)
    SetTextFont(4)
    SetTextScale(0.35, 0.35)
    SetTextColour(255, 255, 255, 200)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

-- Toggle HUD
RegisterNetEvent('lyxpanel:toggleAdminHud', function(enabled)
    hudEnabled = enabled
end)

-- NUI callback for toggling HUD
RegisterNUICallback('toggleAdminHud', function(data, cb)
    hudEnabled = data.enabled
    cb({})
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- OUTFIT SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════════

-- Get current outfit data
RegisterNUICallback('getCurrentOutfit', function(data, cb)
    local ped = PlayerPedId()
    local outfitData = {}
    
    -- Get all components
    for i = 0, 11 do
        outfitData['comp_' .. i] = {
            drawable = GetPedDrawableVariation(ped, i),
            texture = GetPedTextureVariation(ped, i)
        }
    end
    
    -- Get all props
    for i = 0, 8 do
        outfitData['prop_' .. i] = {
            drawable = GetPedPropIndex(ped, i),
            texture = GetPedPropTextureIndex(ped, i)
        }
    end
    
    cb(outfitData)
end)

-- Load outfit
RegisterNetEvent('lyxpanel:loadOutfit', function(outfitData)
    local ped = PlayerPedId()
    
    -- Apply components
    for i = 0, 11 do
        local comp = outfitData['comp_' .. i]
        if comp then
            SetPedComponentVariation(ped, i, comp.drawable, comp.texture, 0)
        end
    end
    
    -- Apply props
    for i = 0, 8 do
        local prop = outfitData['prop_' .. i]
        if prop and prop.drawable >= 0 then
            SetPedPropIndex(ped, i, prop.drawable, prop.texture, true)
        else
            ClearPedProp(ped, i)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- PRIVATE MESSAGE FROM REPORT
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('lyxpanel:privateMessage', function(fromName, message, msgType)
    -- Display notification
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName('~b~[ADMIN] ' .. fromName .. ':~s~ ' .. message)
    EndTextCommandThefeedPostTicker(true, true)
    
    -- Also send to NUI
    SendNUIMessage({
        action = 'privateMessage',
        from = fromName,
        message = message,
        type = msgType
    })
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- NUI CALLBACKS FOR NEW FEATURES
-- ═══════════════════════════════════════════════════════════════════════════════

-- Save current position as favorite
RegisterNUICallback('saveCurrentPosition', function(data, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    
    _TriggerPanelEvent('lyxpanel:action:saveTeleportFavorite', data.name, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = heading
    })
    cb({ success = true })
end)

-- Get teleport favorites
RegisterNUICallback('getTeleportFavorites', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getTeleportFavorites', function(favorites)
        cb(favorites)
    end)
end)

-- Get weapon kits
RegisterNUICallback('getWeaponKits', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getWeaponKits', function(kits)
        cb(kits)
    end)
end)

-- Export bans
RegisterNUICallback('exportBans', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:exportBans', function(result)
        cb(result)
    end)
end)

-- Get admin rankings
RegisterNUICallback('getAdminRankings', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getAdminRankings', function(rankings)
        cb(rankings)
    end, data.period)
end)

-- Get player outfits
RegisterNUICallback('getMyOutfits', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getPlayerOutfits', function(outfits)
        cb(outfits)
    end)
end)

print('[LyxPanel v4.5] Client features loaded')
