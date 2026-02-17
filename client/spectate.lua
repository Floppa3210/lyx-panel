--[[
    LyxPanel - Advanced Spectate System
    Supports routing bucket handling for dimension-safe spectating
    Based on vAdmin spectate system
]]

local Spectate = {}

-- State tracking
local isSpectating = false
local spectatingTarget = nil
local originalCoords = nil
local originalBucket = nil

-- Local references
local PlayerPedId = PlayerPedId
local GetEntityCoords = GetEntityCoords
local SetEntityCoords = SetEntityCoords
local NetworkSetInSpectatorMode = NetworkSetInSpectatorMode
local GetPlayerPed = GetPlayerPed
local GetPlayerServerId = GetPlayerServerId
local PlayerId = PlayerId
local SetEntityVisible = SetEntityVisible
local FreezeEntityPosition = FreezeEntityPosition
local SetEntityCollision = SetEntityCollision
local SetEntityInvincible = SetEntityInvincible
local DoScreenFadeOut = DoScreenFadeOut
local DoScreenFadeIn = DoScreenFadeIn
local IsScreenFadedOut = IsScreenFadedOut

local function _TriggerPanelEvent(eventName, ...)
    if type(LyxPanelSecureTrigger) == 'function' then
        return LyxPanelSecureTrigger(eventName, ...)
    end
    return TriggerServerEvent(eventName, ...)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- SPECTATE LOGIC
-- ═══════════════════════════════════════════════════════════════════════════════

--- Start spectating a player
---@param targetId number Target player server ID
---@param targetCoords vector3 Target coordinates
function Spectate.Start(targetId, targetCoords)
    if isSpectating then
        local targetPed = GetPlayerPed(GetPlayerFromServerId(targetId))
        if targetPed and targetPed ~= 0 then
            spectatingTarget = targetId
            NetworkSetInSpectatorMode(true, targetPed)
        end
        return
    end
    
    local ped = PlayerPedId()
    
    -- Store original state
    originalCoords = GetEntityCoords(ped)
    
    -- Fade out for smooth transition
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do
        Wait(10)
    end
    
    -- Make player invisible and frozen
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    
    -- Teleport to target area
    SetEntityCoords(ped, targetCoords.x, targetCoords.y, targetCoords.z + 10.0, false, false, false, false)
    
    Wait(100)
    
    -- Get target ped
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetId))
    
    if targetPed and targetPed ~= 0 then
        -- Enable spectate mode
        NetworkSetInSpectatorMode(true, targetPed)
        isSpectating = true
        spectatingTarget = targetId
        
        DoScreenFadeIn(500)
        
        -- Notify user
        TriggerEvent('chat:addMessage', {
            color = {255, 165, 0},
            multiline = true,
            args = {'LyxPanel', ('🔍 Especteando a jugador ID: %d - Presiona E para salir'):format(targetId)}
        })
    else
        -- Target not found, revert
        Spectate.Stop()
    end
end

--- Stop spectating
function Spectate.Stop()
    if not isSpectating then return end
    
    local ped = PlayerPedId()
    
    -- Fade out
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do
        Wait(10)
    end
    
    -- Disable spectate mode
    NetworkSetInSpectatorMode(false, ped)
    
    -- Restore original position
    if originalCoords then
        SetEntityCoords(ped, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false, false)
    end
    
    Wait(100)
    
    -- Restore visibility and controls
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    
    -- Reset state
    isSpectating = false
    spectatingTarget = nil
    originalCoords = nil
    
    DoScreenFadeIn(500)
    
    -- Notify server to restore routing bucket
    _TriggerPanelEvent('lyxpanel:spectate:end')
    
    TriggerEvent('chat:addMessage', {
        color = {0, 255, 0},
        multiline = true,
        args = {'LyxPanel', '✅ Spectate terminado'}
    })
end

--- Check if currently spectating
---@return boolean
function Spectate.IsActive()
    return isSpectating
end

--- Get current spectate target
---@return number|nil targetId
function Spectate.GetTarget()
    return spectatingTarget
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- EVENT HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Server tells us to start spectating
RegisterNetEvent('lyxpanel:spectate:start')
AddEventHandler('lyxpanel:spectate:start', function(targetId, targetCoords)
    Spectate.Start(targetId, targetCoords)
end)

-- Server tells us to stop spectating
RegisterNetEvent('lyxpanel:spectate:stop')
AddEventHandler('lyxpanel:spectate:stop', function()
    Spectate.Stop()
end)

-- Key handler for exiting spectate
CreateThread(function()
    while true do
        Wait(0)
        
        if isSpectating then
            -- E key to exit
            if IsControlJustPressed(0, 38) then
                Spectate.Stop()
            end
            
            -- Follow target if they move
            local targetPed = GetPlayerPed(GetPlayerFromServerId(spectatingTarget))
            if targetPed and targetPed ~= 0 then
                NetworkSetInSpectatorMode(true, targetPed)
            else
                -- Target left, stop spectating
                Spectate.Stop()
            end
        else
            Wait(500)
        end
    end
end)

-- Export functions
exports('StartSpectate', Spectate.Start)
exports('StopSpectate', Spectate.Stop)
exports('IsSpectating', Spectate.IsActive)

return Spectate
