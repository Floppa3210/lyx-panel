--[[
    LyxPanel - Toggles System
    Handles toggle states for admin features like noclip, godmode, etc.
    Based on WaveAdmin toggles pattern
]]

local Toggles = {}

-- Toggle states
local toggleStates = {
    noclip = false,
    godmode = false,
    invisible = false,
    infiniteStamina = false,
    superJump = false,
    speedboost = false,
    nitro = false,
    vehicleGodmode = false
}

-- Local references
local PlayerPedId = PlayerPedId
local SetEntityInvincible = SetEntityInvincible
local SetEntityVisible = SetEntityVisible
local SetPedInfiniteStamina = SetRunSprintMultiplierForPlayer
local SetSuperJumpThisFrame = SetSuperJumpThisFrame
local GetEntityCoords = GetEntityCoords
local GetEntityHeading = GetEntityHeading
local GetEntityVelocity = GetEntityVelocity
local SetEntityVelocity = SetEntityVelocity
local SetEntityCoordsNoOffset = SetEntityCoordsNoOffset
local IsControlPressed = IsControlPressed
local GetGameplayCamRelativeHeading = GetGameplayCamRelativeHeading
local GetGameplayCamRelativePitch = GetGameplayCamRelativePitch
local GetGameplayCamRot = GetGameplayCamRot
local SetEntityRotation = SetEntityRotation
local FreezeEntityPosition = FreezeEntityPosition

-- Noclip configuration
local NOCLIP_SPEED_SLOW = 0.5
local NOCLIP_SPEED_NORMAL = 2.0
local NOCLIP_SPEED_FAST = 5.0
local NOCLIP_SPEED_SUPER = 10.0

-- ═══════════════════════════════════════════════════════════════════════════════
-- TOGGLE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════════

--- Toggle godmode
---@param enable boolean|nil Explicit state or nil to toggle
function Toggles.Godmode(enable)
    if enable == nil then
        toggleStates.godmode = not toggleStates.godmode
    else
        toggleStates.godmode = enable
    end
    
    local ped = PlayerPedId()
    SetEntityInvincible(ped, toggleStates.godmode)
    SetPlayerInvincible(PlayerId(), toggleStates.godmode)
    
    return toggleStates.godmode
end

--- Toggle invisibility
---@param enable boolean|nil
function Toggles.Invisible(enable)
    if enable == nil then
        toggleStates.invisible = not toggleStates.invisible
    else
        toggleStates.invisible = enable
    end
    
    local ped = PlayerPedId()
    SetEntityVisible(ped, not toggleStates.invisible, false)
    
    return toggleStates.invisible
end

--- Toggle noclip
---@param enable boolean|nil
function Toggles.Noclip(enable)
    if enable == nil then
        toggleStates.noclip = not toggleStates.noclip
    else
        toggleStates.noclip = enable
    end
    
    local ped = PlayerPedId()
    
    if toggleStates.noclip then
        FreezeEntityPosition(ped, true)
        SetEntityCollision(ped, false, false)
        SetEntityInvincible(ped, true)
        SetEntityVisible(ped, false, false)
    else
        FreezeEntityPosition(ped, false)
        SetEntityCollision(ped, true, true)
        SetEntityInvincible(ped, toggleStates.godmode) -- Restore godmode state
        SetEntityVisible(ped, not toggleStates.invisible, false) -- Restore invisible state
    end
    
    return toggleStates.noclip
end

--- Toggle infinite stamina
---@param enable boolean|nil
function Toggles.InfiniteStamina(enable)
    if enable == nil then
        toggleStates.infiniteStamina = not toggleStates.infiniteStamina
    else
        toggleStates.infiniteStamina = enable
    end
    
    return toggleStates.infiniteStamina
end

--- Toggle super jump
---@param enable boolean|nil
function Toggles.SuperJump(enable)
    if enable == nil then
        toggleStates.superJump = not toggleStates.superJump
    else
        toggleStates.superJump = enable
    end
    
    return toggleStates.superJump
end

--- Toggle speedboost (makes player run/drive faster)
---@param enable boolean|nil
function Toggles.Speedboost(enable)
    if enable == nil then
        toggleStates.speedboost = not toggleStates.speedboost
    else
        toggleStates.speedboost = enable
    end
    
    local playerId = PlayerId()
    if toggleStates.speedboost then
        SetRunSprintMultiplierForPlayer(playerId, 1.49)
        SetSwimMultiplierForPlayer(playerId, 1.49)
    else
        SetRunSprintMultiplierForPlayer(playerId, 1.0)
        SetSwimMultiplierForPlayer(playerId, 1.0)
    end
    
    return toggleStates.speedboost
end

--- Toggle nitro (instant vehicle turbo)
---@param enable boolean|nil
function Toggles.Nitro(enable)
    if enable == nil then
        toggleStates.nitro = not toggleStates.nitro
    else
        toggleStates.nitro = enable
    end
    
    return toggleStates.nitro
end

--- Toggle vehicle godmode
---@param enable boolean|nil
function Toggles.VehicleGodmode(enable)
    if enable == nil then
        toggleStates.vehicleGodmode = not toggleStates.vehicleGodmode
    else
        toggleStates.vehicleGodmode = enable
    end
    
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle ~= 0 then
        SetEntityInvincible(vehicle, toggleStates.vehicleGodmode)
        SetVehicleCanBeVisiblyDamaged(vehicle, not toggleStates.vehicleGodmode)
        SetVehicleEngineCanDegrade(vehicle, not toggleStates.vehicleGodmode)
        SetVehicleWheelsCanBreak(vehicle, not toggleStates.vehicleGodmode)
    end
    
    return toggleStates.vehicleGodmode
end

--- Get all toggle states
---@return table states
function Toggles.GetStates()
    return toggleStates
end

--- Set toggle from server
---@param toggleName string
---@param state boolean
function Toggles.SetFromServer(toggleName, state)
    if toggleName == 'godmode' then
        Toggles.Godmode(state)
    elseif toggleName == 'invisible' then
        Toggles.Invisible(state)
    elseif toggleName == 'noclip' then
        Toggles.Noclip(state)
    elseif toggleName == 'infiniteStamina' then
        Toggles.InfiniteStamina(state)
    elseif toggleName == 'superJump' then
        Toggles.SuperJump(state)
    elseif toggleName == 'speedboost' then
        Toggles.Speedboost(state)
    elseif toggleName == 'nitro' then
        Toggles.Nitro(state)
    elseif toggleName == 'vehicleGodmode' then
        Toggles.VehicleGodmode(state)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- NOCLIP MOVEMENT HANDLER
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        if toggleStates.noclip then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            
            -- Get camera rotation for direction
            local camRot = GetGameplayCamRot(2)
            local heading = GetGameplayCamRelativeHeading()
            local pitch = GetGameplayCamRelativePitch()
            
            -- Calculate speed based on controls
            local speed = NOCLIP_SPEED_NORMAL
            if IsControlPressed(0, 21) then -- Shift
                speed = NOCLIP_SPEED_FAST
            elseif IsControlPressed(0, 36) then -- Ctrl
                speed = NOCLIP_SPEED_SLOW
            elseif IsControlPressed(0, 21) and IsControlPressed(0, 36) then
                speed = NOCLIP_SPEED_SUPER
            end
            
            -- Movement direction
            local fwd = 0.0
            local side = 0.0
            local up = 0.0
            
            -- W/S - Forward/Backward
            if IsControlPressed(0, 32) then fwd = speed end
            if IsControlPressed(0, 33) then fwd = -speed end
            
            -- A/D - Left/Right
            if IsControlPressed(0, 34) then side = -speed end
            if IsControlPressed(0, 35) then side = speed end
            
            -- Space/Ctrl - Up/Down
            if IsControlPressed(0, 22) then up = speed end
            if IsControlPressed(0, 44) then up = -speed end
            
            if fwd ~= 0 or side ~= 0 or up ~= 0 then
                -- Calculate new position based on camera direction
                local angle = math.rad(camRot.z)
                local newX = coords.x + (fwd * math.sin(-angle)) + (side * math.cos(angle))
                local newY = coords.y + (fwd * math.cos(-angle)) + (side * math.sin(angle))
                local newZ = coords.z + up
                
                SetEntityCoordsNoOffset(ped, newX, newY, newZ, true, true, true)
                SetEntityHeading(ped, camRot.z)
            end
            
            -- Apply camera rotation to ped
            SetEntityRotation(ped, 0.0, 0.0, camRot.z, 2, true)
            
            Wait(0)
        else
            Wait(200)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- EFFECT HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        
        -- Infinite stamina
        if toggleStates.infiniteStamina then
            RestorePlayerStamina(PlayerId(), 100.0)
        end
        
        -- Super jump
        if toggleStates.superJump then
            SetSuperJumpThisFrame(PlayerId())
        end
        
        -- Nitro boost
        if toggleStates.nitro then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                -- Apply turbo when accelerating
                if IsControlPressed(0, 71) then -- W key (accelerate)
                    SetVehicleCurrentRpm(vehicle, 1.0)
                    SetVehicleEngineTorqueMultiplier(vehicle, 3.0)
                    SetVehicleCheatPowerIncrease(vehicle, 1.5)
                end
            end
        end
        
        -- Vehicle godmode maintenance
        if toggleStates.vehicleGodmode then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 then
                SetEntityInvincible(vehicle, true)
                SetVehicleFixed(vehicle)
                SetVehicleEngineHealth(vehicle, 1000.0)
                SetVehicleBodyHealth(vehicle, 1000.0)
            end
        end
        
        Wait(0)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- EVENT HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('lyxpanel:toggles:set')
AddEventHandler('lyxpanel:toggles:set', function(toggleName, state)
    Toggles.SetFromServer(toggleName, state)
    
    local statusText = state and '✅ ACTIVADO' or '❌ DESACTIVADO'
    TriggerEvent('chat:addMessage', {
        color = {0, 255, 255},
        multiline = true,
        args = {'LyxPanel', ('%s: %s'):format(toggleName:upper(), statusText)}
    })
end)

-- Export functions
exports('ToggleGodmode', Toggles.Godmode)
exports('ToggleInvisible', Toggles.Invisible)
exports('ToggleNoclip', Toggles.Noclip)
exports('ToggleSpeedboost', Toggles.Speedboost)
exports('ToggleNitro', Toggles.Nitro)
exports('ToggleVehicleGodmode', Toggles.VehicleGodmode)
exports('GetToggleStates', Toggles.GetStates)

return Toggles
