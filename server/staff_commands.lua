--[[
    
                        LYXPANEL v4.0 - STAFF COMMANDS                            
                        Optimizado para ESX Legacy 1.9+                            
    

    FUNCIONALIDADES:
    - Presionar E cuando muerto = revivir (SOLO ADMINS)
    - /infinitebullets on/off - Municion infinita (staff)

    SEGURIDAD:
    - Toda validacin es server-side
    - El cliente solicita, el servidor autoriza
]]

local ESX = nil
local StaffStates = {
    infiniteBullets = {}, -- Players with infinite bullets enabled
    instantRespawn = {}   -- Players with instant respawn enabled (can press E to revive)
}

-- 
-- INICIALIZACIN ESX
-- 

CreateThread(function()
    local resolved = ESX
    if LyxPanel and LyxPanel.WaitForESX then
        resolved = LyxPanel.WaitForESX(15000)
    end

    if not resolved then
        print('^1[LyxPanel Staff]^7 ESX no disponible (timeout).')
        return
    end

    ESX = resolved
    _G.ESX = _G.ESX or resolved

    print('^2[LyxPanel Staff]^7 ESX cargado correctamente')
end)

-- Cleanup on disconnect
AddEventHandler('playerDropped', function()
    local src = source
    StaffStates.infiniteBullets[src] = nil
    StaffStates.instantRespawn[src] = nil
end)

-- 
-- PERMISOS
-- 

local function HasStaffPermission(source, cfg)
    if not source or source <= 0 then return false end

    -- ACE permission (txAdmin, consola, etc)
    if cfg and cfg.acePermission and cfg.acePermission ~= '' then
        if IsPlayerAceAllowed(source, cfg.acePermission) then return true end
    end

    if type(HasPanelAccess) == 'function' then
        local access, group = HasPanelAccess(source)
        if access and group then
            local allowedGroups = cfg and cfg.allowedGroups or { 'superadmin', 'admin', 'master', 'owner' }
            for _, allowed in ipairs(allowedGroups) do
                if group == allowed then return true end
            end
        end
    end

    -- ESX group
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local group = xPlayer.getGroup()
            local allowedGroups = cfg and cfg.allowedGroups or { 'superadmin', 'admin', 'master', 'owner' }
            for _, allowed in ipairs(allowedGroups) do
                if group == allowed then return true end
            end
        end
    end

    return false
end

local function NotifyStaff(source, message, msgType)
    TriggerClientEvent('lyxpanel:notify', source, msgType or 'info', message)
end

local function LogStaffAction(source, action, details)
    local name = GetPlayerName(source) or 'Unknown'
    print(string.format('^5[LyxPanel Staff]^7 %s ejecuto %s: %s', name, action, details or ''))
end

-- 
-- v4.4 HOTFIX: SISTEMA DE ADMIN STATUS Y STAFF REVIVE TOGGLE
-- El revive con E ahora est DESACTIVADO por defecto y solo admins pueden activarlo
-- 

-- Track staff revive states per player
local StaffReviveEnabled = {}

-- Cleanup on disconnect
AddEventHandler('playerDropped', function()
    local src = source
    StaffReviveEnabled[src] = nil
end)

-- v4.4: El cliente pregunta si es admin al conectar
RegisterNetEvent('lyxpanel:staffcmd:checkAdminStatus', function()
    local src = source
    local cfg = Config.StaffCommands and Config.StaffCommands.staffRevive
    local isAdmin = HasStaffPermission(src, cfg)
    TriggerClientEvent('lyxpanel:staffcmd:setAdminStatus', src, isAdmin)
end)

-- v4.4: Comando para que admins activen/desactiven su modo staff revive
RegisterCommand('staffrevive', function(source, args)
    local src = source
    if src == 0 then return end -- Consola no puede usar esto

    local cfg = Config.StaffCommands and Config.StaffCommands.staffRevive

    -- Verificar permisos
    if not HasStaffPermission(src, cfg) then
        TriggerClientEvent('lyxpanel:notify', src, 'error', 'Sin permisos para usar Staff Revive')
        return
    end

    -- Toggle o set explcito
    local action = args[1] and string.lower(args[1])
    local current = StaffReviveEnabled[src] or false
    local newState

    if action == 'on' then
        newState = true
    elseif action == 'off' then
        newState = false
    else
        newState = not current
    end

    StaffReviveEnabled[src] = newState
    TriggerClientEvent('lyxpanel:staffcmd:toggleStaffRevive', src, newState)
    LogStaffAction(src, 'staffRevive', newState and 'ACTIVADO' or 'DESACTIVADO')
end, false)

-- 
-- SISTEMA DE REVIVE CON TECLA E (SOLO ADMINS CON MODO ACTIVADO)
-- Cuando el jugador est muerto y presiona E, solicita revive al servidor
-- El servidor verifica permisos Y que tenga el modo activado
-- 

-- El cliente solicita revivir cuando presiona E estando muerto
RegisterNetEvent('lyxpanel:staffcmd:requestRevive', function()
    local src = source

    -- Obtener config de revive
    local cfg = Config.StaffCommands and Config.StaffCommands.staffRevive

    -- Verificar permisos
    if not HasStaffPermission(src, cfg) then
        return -- No es admin, silencioso
    end

    -- v4.4: Verificar que tiene el modo staff revive activado
    if not StaffReviveEnabled[src] then
        return -- No tiene el modo activado, silencioso
    end

    -- Es admin Y tiene el modo activado, autorizar revive
    TriggerClientEvent('lyxpanel:staffcmd:doRevive', src)
    LogStaffAction(src, 'staffRevive', 'Revivido con tecla E')
end)

-- Export para verificar si un jugador puede revivir
exports('CanPlayerRevive', function(source)
    local cfg = Config.StaffCommands and Config.StaffCommands.staffRevive
    return HasStaffPermission(source, cfg) and StaffReviveEnabled[source]
end)

-- Export para verificar si tiene staff revive habilitado
exports('IsStaffReviveEnabled', function(source)
    return StaffReviveEnabled[source] or false
end)

-- 
-- INFINITE BULLETS
-- 

local function RegisterInfiniteBulletsCommand()
    local cfg = Config.StaffCommands and Config.StaffCommands.infiniteBullets
    if not cfg or not cfg.enabled then return end

    RegisterCommand(cfg.command, function(source, args)
        if not HasStaffPermission(source, cfg) then
            return NotifyStaff(source, 'Sin permiso', 'error')
        end

        -- Parse arguments: /infinitebullets [targetId] [on/off]
        local targetId = nil
        local action = nil
        
        if #args >= 2 then
            -- /infinitebullets 5 on => targetId=5, action=on
            targetId = tonumber(args[1])
            action = string.lower(args[2])
        elseif #args == 1 then
            -- /infinitebullets on => self, action=on
            -- /infinitebullets 5 => targetId=5, toggle
            local firstArg = string.lower(args[1])
            if firstArg == 'on' or firstArg == 'off' then
                action = firstArg
                targetId = source
            else
                targetId = tonumber(args[1])
                if not targetId then
                    return NotifyStaff(source, 'Uso: /' .. cfg.command .. ' [id] [on/off]', 'warning')
                end
            end
        else
            -- /infinitebullets => toggle self
            targetId = source
        end
        
        targetId = targetId or source
        
        -- Validate target exists
        if GetPlayerName(targetId) == nil then
            return NotifyStaff(source, 'Jugador ID ' .. targetId .. ' no encontrado', 'error')
        end

        local current = StaffStates.infiniteBullets[targetId] or false
        local newState

        if action == 'on' then
            newState = true
        elseif action == 'off' then
            newState = false
        else
            newState = not current
        end

        StaffStates.infiniteBullets[targetId] = newState
        TriggerClientEvent('lyxpanel:staffcmd:setInfiniteBullets', targetId, newState)

        local statusText = newState and ' ACTIVADO' or ' DESACTIVADO'
        local targetName = GetPlayerName(targetId)
        
        if targetId == source then
            NotifyStaff(source, 'Infinite Bullets: ' .. statusText, newState and 'success' or 'info')
        else
            NotifyStaff(source, 'Infinite Bullets para ' .. targetName .. ': ' .. statusText, newState and 'success' or 'info')
            NotifyStaff(targetId, 'Un admin te activo Infinite Bullets: ' .. statusText, newState and 'success' or 'info')
        end
        
        LogStaffAction(source, 'infiniteBullets', (newState and 'ACTIVADO' or 'DESACTIVADO') .. ' para ' .. targetName)
    end, false)

    print('^5[LyxPanel]^7 Comando /' .. cfg.command .. ' registrado')
end

-- Refill request handler
RegisterNetEvent('lyxpanel:staffcmd:requestAmmoRefill', function(weaponHash, maxAmmo)
    local src = source
    if not StaffStates.infiniteBullets[src] then return end

    local cfg = Config.StaffCommands and Config.StaffCommands.infiniteBullets
    if not cfg or not HasStaffPermission(src, cfg) then
        StaffStates.infiniteBullets[src] = nil
        return
    end

    TriggerClientEvent('lyxpanel:staffcmd:doAmmoRefill', src, weaponHash, maxAmmo)
end)

exports('IsInfiniteBulletsEnabled', function(source)
    return StaffStates.infiniteBullets[source] or false
end)

-- 
-- INSTANT RESPAWN SYSTEM
-- /instantrespawn [id] - Permite que un jugador pueda presionar E para revivir
-- Deshabilitado por defecto para todos
-- 

local function RegisterInstantRespawnCommand()
    RegisterCommand('instantrespawn', function(source, args)
        local cfg = Config.StaffCommands and Config.StaffCommands.staffRevive
        
        if not HasStaffPermission(source, cfg) then
            return NotifyStaff(source, 'Sin permiso para usar Instant Respawn', 'error')
        end
        
        -- Parse target
        local targetId = tonumber(args[1])
        if not targetId then
            return NotifyStaff(source, 'Uso: /instantrespawn [id]', 'warning')
        end
        
        -- Validate target exists
        if GetPlayerName(targetId) == nil then
            return NotifyStaff(source, 'Jugador ID ' .. targetId .. ' no encontrado', 'error')
        end
        
        -- Toggle instant respawn for target
        local current = StaffStates.instantRespawn[targetId] or false
        local newState = not current
        
        StaffStates.instantRespawn[targetId] = newState
        TriggerClientEvent('lyxpanel:staffcmd:setInstantRespawn', targetId, newState)
        
        local statusText = newState and ' ACTIVADO' or ' DESACTIVADO'
        local targetName = GetPlayerName(targetId)
        
        NotifyStaff(source, 'Instant Respawn para ' .. targetName .. ': ' .. statusText, newState and 'success' or 'info')
        NotifyStaff(targetId, 'Un admin te ' .. (newState and 'habilito' or 'deshabilito') .. ' Instant Respawn (E para revivir)', newState and 'success' or 'info')
        
        LogStaffAction(source, 'instantRespawn', (newState and 'ACTIVADO' or 'DESACTIVADO') .. ' para ' .. targetName)
    end, false)
    
    print('^5[LyxPanel]^7 Comando /instantrespawn registrado')
end

-- Instant respawn request handler (for non-admins with permission granted)
RegisterNetEvent('lyxpanel:staffcmd:requestInstantRespawn', function()
    local src = source
    
    -- Check if player has instant respawn enabled by an admin
    if not StaffStates.instantRespawn[src] then
        return -- Not enabled for this player
    end
    
    -- Authorize revive
    TriggerClientEvent('lyxpanel:staffcmd:doRevive', src)
    LogStaffAction(src, 'instantRespawn', 'Revivido con tecla E (dado por admin)')
end)

exports('IsInstantRespawnEnabled', function(source)
    return StaffStates.instantRespawn[source] or false
end)

-- 
-- INICIALIZACIN
-- 

CreateThread(function()
    Wait(500) -- Esperar a que Config est disponible
    RegisterInfiniteBulletsCommand()
    RegisterInstantRespawnCommand()
    print('^2[LyxPanel]^7 Staff Commands cargados: Revive con E (admins), /infinitebullets, /instantrespawn')
end)



