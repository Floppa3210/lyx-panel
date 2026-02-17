--[[
    LyxPanel v4.0 - Extended Client Features
    Jail system, mute system, and additional UI handlers
]]

local isJailed = false
local jailTime = 0
local jailReason = ''
local isMuted = false
local muteType = nil

local function _TriggerPanelEvent(eventName, ...)
    if type(LyxPanelSecureTrigger) == 'function' then
        return LyxPanelSecureTrigger(eventName, ...)
    end
    return TriggerServerEvent(eventName, ...)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- JAIL SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('lyxpanel:setJailed', function(jailed, time, reason)
    isJailed = jailed
    jailTime = time or 0
    jailReason = reason or ''
    
    if jailed then
        -- Start jail UI
        CreateThread(function()
            while isJailed do
                Wait(0)
                -- Draw jail overlay
                SetTextFont(4)
                SetTextScale(0.5, 0.5)
                SetTextColour(255, 100, 100, 255)
                SetTextCentre(true)
                SetTextOutline()
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName('🔒 ENCARCELADO - ' .. jailReason)
                EndTextCommandDisplayText(0.5, 0.02)
                
                -- Block controls
                DisableControlAction(0, 21, true)  -- Sprint
                DisableControlAction(0, 24, true)  -- Attack
                DisableControlAction(0, 25, true)  -- Aim
                DisableControlAction(0, 47, true)  -- Weapon
                DisableControlAction(0, 75, true)  -- Exit vehicle
            end
        end)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- MUTE SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('lyxpanel:setMuted', function(muted, mType, time)
    isMuted = muted
    muteType = mType
    
    if muted and mType == 'voice' then
        -- Disable voice
        NetworkSetTalkerProximity(0.0)
    else
        -- Re-enable voice
        NetworkSetTalkerProximity(10.0)
    end
end)

-- Export for chat resources
exports('IsPlayerMuted', function()
    return isMuted, muteType
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- CLIPBOARD COPY
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('lyxpanel:copyToClipboard', function(text)
    SendNUIMessage({
        action = 'copyToClipboard',
        text = text
    })
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- SERVER CONTROL - REMOVED FOR SECURITY
-- Restart, KickAll, and Resource management have been removed.
-- Use txAdmin for server management.
-- ═══════════════════════════════════════════════════════════════════════════════

-- Advanced bans
RegisterNUICallback('banOffline', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:banOffline', data.identifier, data.reason, data.duration, data.playerName)
    cb({})
end)

RegisterNUICallback('banIPRange', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:banIPRange', data.ipRange, data.reason)
    cb({})
end)

RegisterNUICallback('reduceBan', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:reduceBan', data.banId, data.hours)
    cb({})
end)

-- Warnings
RegisterNUICallback('warnWithEscalation', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:warnWithEscalation', data.targetId, data.reason)
    cb({})
end)

RegisterNUICallback('clearWarnings', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:clearWarnings', data.targetId)
    cb({})
end)

-- Jail
RegisterNUICallback('jail', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:jail', data.targetId, data.time, data.reason)
    cb({})
end)

RegisterNUICallback('unjail', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:unjail', data.targetId)
    cb({})
end)

-- Mute
RegisterNUICallback('muteChat', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:muteChat', data.targetId, data.time)
    cb({})
end)

RegisterNUICallback('muteVoice', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:muteVoice', data.targetId, data.time)
    cb({})
end)

RegisterNUICallback('unmute', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:unmute', data.targetId)
    cb({})
end)

-- Whitelist
RegisterNUICallback('addWhitelist', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:addWhitelist', data.identifier, data.playerName)
    cb({})
end)

RegisterNUICallback('removeWhitelist', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:removeWhitelist', data.identifier)
    cb({})
end)

RegisterNUICallback('getWhitelist', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getWhitelist', function(list)
        cb(list or {})
    end)
end)

-- Player history/search
RegisterNUICallback('searchPlayer', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:searchPlayer', function(results)
        cb(results or {})
    end, data.search)
end)

RegisterNUICallback('getPlayerHistory', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getPlayerHistory', function(history)
        cb(history or {})
    end, data.identifier)
end)

-- Server stats
RegisterNUICallback('getServerStats', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getServerStats', function(stats)
        cb(stats or {})
    end)
end)

RegisterNUICallback('getResourceList', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getResourceList', function(list)
        cb(list or {})
    end)
end)

-- Schedule announce
RegisterNUICallback('scheduleAnnounce', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:scheduleAnnounce', data.message, data.delay, data.repeat)
    cb({})
end)

-- Garage
RegisterNUICallback('getPlayerGarage', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getPlayerGarage', function(vehicles)
        cb(vehicles or {})
    end, data.targetId)
end)

RegisterNUICallback('giveVehicle', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:giveVehicle', data.targetId, data.vehicle, data.plate)
    cb({})
end)

RegisterNUICallback('deleteGarageVehicle', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:deleteGarageVehicle', data.targetId, data.plate)
    cb({})
end)

-- Licenses
RegisterNUICallback('getPlayerLicenses', function(data, cb)
    ESX.TriggerServerCallback('lyxpanel:getPlayerLicenses', function(licenses)
        cb(licenses or {})
    end, data.targetId)
end)

RegisterNUICallback('giveLicense', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:giveLicense', data.targetId, data.license)
    cb({})
end)

RegisterNUICallback('removeLicense', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:removeLicense', data.targetId, data.license)
    cb({})
end)

-- Copy position
RegisterNUICallback('copyPosition', function(data, cb)
    _TriggerPanelEvent('lyxpanel:action:copyPosition', data.targetId)
    cb({})
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- VEHICLE MANAGEMENT FUNCTIONS (v4.3)
-- Note: These actions are handled by RegisterNUICallback('action') in main.lua
-- The JavaScript sends via sendAction() which goes to the 'action' NUI callback
-- The server then triggers events back to client for execution
-- ═══════════════════════════════════════════════════════════════════════════════

print('[LyxPanel v4.3] Extended client features loaded')

