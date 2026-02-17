--[[
    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                    LYXPANEL v4.0 - STAFF COMMANDS (CLIENT)                   ║
    ╚═══════════════════════════════════════════════════════════════════════════════╝

    FUNCIONALIDADES:
    - Cuando estás muerto, aparece texto "Presiona [E] para revivir"
    - Si eres admin y presionas E, revivis
    - Si NO eres admin, no pasa nada
    - Munición infinita controlada por servidor

    SEGURIDAD:
    - El cliente solo SOLICITA, el servidor AUTORIZA
    - No hay bypass posible desde el cliente
]]

-- ═══════════════════════════════════════════════════════════════════════════════
-- ESTADO LOCAL
-- v4.4 HOTFIX: Revive solo para admins, debe activarse manualmente
-- ═══════════════════════════════════════════════════════════════════════════════

local LocalStates = {
    infiniteBullets = false,
    isDead = false,
    lastReviveRequest = 0,
    -- v4.4: NUEVOS ESTADOS
    isAdmin = false,           -- Se verifica con el servidor
    staffReviveEnabled = false, -- El admin debe activarlo con /staffrevive
    instantRespawnEnabled = false -- Dado por un admin con /instantrespawn
}

local function _TriggerPanelEvent(eventName, ...)
    if type(LyxPanelSecureTrigger) == 'function' then
        return LyxPanelSecureTrigger(eventName, ...)
    end
    return TriggerServerEvent(eventName, ...)
end

-- v4.4: Verificar si el jugador es admin al conectar
CreateThread(function()
    Wait(5000) -- Esperar a que ESX cargue
    _TriggerPanelEvent('lyxpanel:staffcmd:checkAdminStatus')
end)

-- v4.4: Recibir confirmación de admin del servidor
RegisterNetEvent('lyxpanel:staffcmd:setAdminStatus', function(isAdmin)
    LocalStates.isAdmin = isAdmin
end)

-- v4.4: Toggle del modo staff revive (solo admins)
RegisterNetEvent('lyxpanel:staffcmd:toggleStaffRevive', function(enabled)
    if LocalStates.isAdmin then
        LocalStates.staffReviveEnabled = enabled

        BeginTextCommandThefeedPost('STRING')
        if enabled then
            AddTextComponentSubstringPlayerName('~g~Staff Revive ACTIVADO~w~ - Presiona E cuando estés muerto')
        else
            AddTextComponentSubstringPlayerName('~r~Staff Revive DESACTIVADO')
        end
        EndTextCommandThefeedPostTicker(true, true)
    end
end)

-- v4.5: Instant respawn dado por admin (para cualquier jugador)
RegisterNetEvent('lyxpanel:staffcmd:setInstantRespawn', function(enabled)
    LocalStates.instantRespawnEnabled = enabled
    
    BeginTextCommandThefeedPost('STRING')
    if enabled then
        AddTextComponentSubstringPlayerName('~g~Instant Respawn ACTIVADO~w~ - Presiona E cuando estés muerto')
    else
        AddTextComponentSubstringPlayerName('~r~Instant Respawn DESACTIVADO')
    end
    EndTextCommandThefeedPostTicker(true, true)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- FUNCIÓN DE REVIVE (método txAdmin + GTA natives)
-- ═══════════════════════════════════════════════════════════════════════════════

local function DoFullRevive()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    -- 1. Resurrección física del motor de GTA (método txAdmin)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)

    -- Actualizar referencia al ped
    Wait(50)
    ped = PlayerPedId()

    -- 2. Restaurar salud y armadura
    SetEntityHealth(ped, 200)
    SetPlayerMaxArmour(PlayerId(), 100)
    SetPedArmour(ped, 100)

    -- 3. Limpiar efectos visuales
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
    ResetPedVisibleDamage(ped)
    ClearPlayerWantedLevel(PlayerId())

    -- 4. Resetear ragdoll
    SetPedToRagdoll(ped, 0, 0, 0, false, false, false)
    SetPedCanRagdoll(ped, true)

    -- 5. Limpiar efectos de pantalla
    AnimpostfxStop('DeathFailOut')
    AnimpostfxStopAll()

    -- 6. Asegurar no invencible
    SetPlayerInvincible(PlayerId(), false)
    SetEntityInvincible(ped, false)

    -- 7. Restaurar controles
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)

    -- 8. Notificar a ESX si existe
    if GetResourceState('esx_ambulancejob') == 'started' then
        TriggerEvent('esx_ambulancejob:revive')
    end

    -- 9. txAdmin heal
    TriggerEvent('txAdmin:client:HealPlayer')

    -- 10. Re-aplicar salud
    Wait(100)
    ped = PlayerPedId()
    if GetEntityHealth(ped) < 200 then
        SetEntityHealth(ped, 200)
    end

    LocalStates.isDead = false
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- SISTEMA DE REVIVE CON TECLA E
-- v4.5: También funciona para jugadores con instantRespawnEnabled
-- ═══════════════════════════════════════════════════════════════════════════════

-- Recibir autorización del servidor
RegisterNetEvent('lyxpanel:staffcmd:doRevive', function()
    DoFullRevive()

    -- Notificación
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName('~g~Has sido revivido.')
    EndTextCommandThefeedPostTicker(true, true)
end)

-- Thread principal: detectar muerte y mostrar UI
-- v4.5: Funciona para admins con staffReviveEnabled O jugadores con instantRespawnEnabled
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local isDead = IsEntityDead(ped) or IsPedFatallyInjured(ped)

        if isDead then
            LocalStates.isDead = true

            -- Determinar si puede revivir con E
            local canReviveWithE = (LocalStates.isAdmin and LocalStates.staffReviveEnabled) or LocalStates.instantRespawnEnabled

            if canReviveWithE then
                -- Mostrar texto en pantalla
                SetTextFont(4)
                SetTextScale(0.5, 0.5)
                SetTextColour(255, 255, 255, 255)
                SetTextOutline()
                SetTextCentre(true)
                SetTextEntry('STRING')
                AddTextComponentString('~w~Presiona ~g~[E]~w~ para revivir')
                DrawText(0.5, 0.8)

                -- Detectar tecla E (38 = E key)
                if IsControlJustPressed(0, 38) then
                    local now = GetGameTimer()
                    -- Cooldown de 2 segundos para evitar spam
                    if now - LocalStates.lastReviveRequest > 2000 then
                        LocalStates.lastReviveRequest = now
                        -- Solicitar revive al servidor
                        if LocalStates.isAdmin and LocalStates.staffReviveEnabled then
                            _TriggerPanelEvent('lyxpanel:staffcmd:requestRevive')
                        elseif LocalStates.instantRespawnEnabled then
                            _TriggerPanelEvent('lyxpanel:staffcmd:requestInstantRespawn')
                        end
                    end
                end
            end

            Wait(0) -- Frame-by-frame cuando estás muerto
        else
            LocalStates.isDead = false
            Wait(500) -- Revisar cada 500ms cuando estás vivo
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- INFINITE BULLETS
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('lyxpanel:staffcmd:setInfiniteBullets', function(enabled)
    LocalStates.infiniteBullets = enabled

    -- Notificación
    BeginTextCommandThefeedPost('STRING')
    if enabled then
        AddTextComponentSubstringPlayerName('~g~Munición Infinita ACTIVADA')
    else
        AddTextComponentSubstringPlayerName('~r~Munición Infinita DESACTIVADA')
    end
    EndTextCommandThefeedPostTicker(true, true)
end)

-- Thread para mantener munición
CreateThread(function()
    while true do
        Wait(100)

        if LocalStates.infiniteBullets then
            local ped = PlayerPedId()
            local _, currentWeapon = GetCurrentPedWeapon(ped, true)

            if currentWeapon ~= `WEAPON_UNARMED` then
                local ammoInClip = GetAmmoInPedWeapon(ped, currentWeapon)
                local maxAmmo = GetMaxAmmoInClip(ped, currentWeapon, true)

                -- Si el cargador está por debajo del 50%, solicitar refill
                if maxAmmo > 0 and ammoInClip < maxAmmo * 0.5 then
                    _TriggerPanelEvent('lyxpanel:staffcmd:requestAmmoRefill', currentWeapon, maxAmmo)
                end
            end
        end
    end
end)

-- Recibir refill autorizado
RegisterNetEvent('lyxpanel:staffcmd:doAmmoRefill', function(weaponHash, maxAmmo)
    local ped = PlayerPedId()
    local _, currentWeapon = GetCurrentPedWeapon(ped, true)

    if currentWeapon == weaponHash then
        SetAmmoInClip(ped, weaponHash, maxAmmo)
        local currentAmmo = GetAmmoInPedWeapon(ped, weaponHash)
        if currentAmmo < 500 then
            SetPedAmmo(ped, weaponHash, 9999)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ═══════════════════════════════════════════════════════════════════════════════

exports('IsInfiniteBulletsActive', function()
    return LocalStates.infiniteBullets
end)

exports('IsDead', function()
    return LocalStates.isDead
end)
