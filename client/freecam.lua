--[[
    LyxPanel v4.3 - ELITE FREECAM SYSTEM
    Framework-agnostic (works with ESX)

    Features:
    - Smooth camera movement with WASD
    - Speed control with scroll wheel
    - FOV adjustment
    - Teleport to camera position
]]

local FreecamActive = false
local FreecamCamera = nil
local FreecamSpeed = 1.0
local FreecamFov = 60.0

local FreecamPos = vector3(0, 0, 0)
local FreecamRot = vector3(0, 0, 0)

-- ═══════════════════════════════════════════════════════════════════════════════
-- FREECAM CONTROLS
-- ═══════════════════════════════════════════════════════════════════════════════

local function ClampRotation(rot)
    local x = rot.x
    if x > 89.0 then x = 89.0 end
    if x < -89.0 then x = -89.0 end
    return vector3(x, 0.0, rot.z)
end

local function GetCamDirection()
    local rot = FreecamRot
    local rotX = math.rad(rot.x)
    local rotZ = math.rad(rot.z)

    local x = -math.sin(rotZ) * math.abs(math.cos(rotX))
    local y = math.cos(rotZ) * math.abs(math.cos(rotX))
    local z = math.sin(rotX)

    return vector3(x, y, z)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- FREECAM API
-- ═══════════════════════════════════════════════════════════════════════════════

function IsFreecamActive()
    return FreecamActive
end

function GetFreecamPosition()
    return FreecamPos
end

function StartFreecam()
    if FreecamActive then return end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- Create camera
    FreecamCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    FreecamPos = pos + vector3(0, 0, 2)
    FreecamRot = vector3(0, 0, heading)
    FreecamFov = 60.0

    SetCamCoord(FreecamCamera, FreecamPos.x, FreecamPos.y, FreecamPos.z)
    SetCamRot(FreecamCamera, FreecamRot.x, FreecamRot.y, FreecamRot.z, 2)
    SetCamFov(FreecamCamera, FreecamFov)
    RenderScriptCams(true, true, 500, true, true)

    -- Hide player
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)

    FreecamActive = true

    -- Start update loop
    CreateThread(function()
        while FreecamActive do
            -- Disable controls
            DisableAllControlActions(0)

            -- Enable specific controls for camera
            EnableControlAction(0, 1, true)  -- Look LR
            EnableControlAction(0, 2, true)  -- Look UD
            EnableControlAction(0, 14, true) -- Scroll up
            EnableControlAction(0, 15, true) -- Scroll down

            -- Mouse look
            local mouseX = GetDisabledControlNormal(0, 1) * 4.0
            local mouseY = GetDisabledControlNormal(0, 2) * 4.0
            FreecamRot = ClampRotation(FreecamRot + vector3(-mouseY, 0, -mouseX))

            -- Movement
            local direction = GetCamDirection()
            local right = vector3(-direction.y, direction.x, 0)
            local movement = vector3(0, 0, 0)

            -- WASD
            if IsDisabledControlPressed(0, 32) then -- W
                movement = movement + direction
            end
            if IsDisabledControlPressed(0, 33) then -- S
                movement = movement - direction
            end
            if IsDisabledControlPressed(0, 34) then -- A
                movement = movement - right
            end
            if IsDisabledControlPressed(0, 35) then -- D
                movement = movement + right
            end

            -- Up/Down
            if IsDisabledControlPressed(0, 44) then -- Q (up)
                movement = movement + vector3(0, 0, 1)
            end
            if IsDisabledControlPressed(0, 38) then -- E (down)
                movement = movement - vector3(0, 0, 1)
            end

            -- Speed control (Shift = fast, Ctrl = slow)
            local speed = FreecamSpeed
            if IsDisabledControlPressed(0, 21) then -- Shift
                speed = speed * 3.0
            end
            if IsDisabledControlPressed(0, 36) then -- Ctrl
                speed = speed * 0.3
            end

            -- Apply movement
            FreecamPos = FreecamPos + (movement * speed)

            -- Scroll wheel for FOV
            if GetDisabledControlNormal(0, 14) > 0 then -- Scroll up
                FreecamFov = math.max(10, FreecamFov - 5)
            end
            if GetDisabledControlNormal(0, 15) > 0 then -- Scroll down
                FreecamFov = math.min(120, FreecamFov + 5)
            end

            -- Update camera
            SetCamCoord(FreecamCamera, FreecamPos.x, FreecamPos.y, FreecamPos.z)
            SetCamRot(FreecamCamera, FreecamRot.x, FreecamRot.y, FreecamRot.z, 2)
            SetCamFov(FreecamCamera, FreecamFov)

            -- Focus area for streaming
            SetFocusPosAndVel(FreecamPos.x, FreecamPos.y, FreecamPos.z, 0, 0, 0)

            -- Draw HUD
            SetTextScale(0.35, 0.35)
            SetTextFont(4)
            SetTextProportional(1)
            SetTextColour(255, 255, 255, 200)
            SetTextEntry("STRING")
            AddTextComponentString(('~b~FREECAM~w~ | Speed: %.1f | FOV: %.0f | [ESC] Exit'):format(speed, FreecamFov))
            DrawText(0.5, 0.02)

            Wait(0)
        end
    end)
end

function StopFreecam(teleportToCamera)
    if not FreecamActive then return end

    local ped = PlayerPedId()

    -- Teleport player to camera position if requested
    if teleportToCamera then
        SetEntityCoords(ped, FreecamPos.x, FreecamPos.y, FreecamPos.z - 1.0)
        SetEntityHeading(ped, FreecamRot.z)
    end

    -- Restore player
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)

    -- Destroy camera
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(FreecamCamera, false)
    ClearFocus()

    FreecamActive = false
    FreecamCamera = nil
end

function ToggleFreecam()
    if FreecamActive then
        StopFreecam(false)
    else
        StartFreecam()
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- NUI CALLBACK
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNUICallback('toggleFreecam', function(data, cb)
    if not IsNuiFocused() then
        cb({ active = FreecamActive, ok = false, error = 'panel_not_focused' })
        return
    end

    ToggleFreecam()
    cb({ active = FreecamActive, ok = true })
end)

-- ESC to exit freecam
CreateThread(function()
    while true do
        Wait(0)
        if FreecamActive and IsControlJustPressed(0, 200) then -- ESC
            StopFreecam(false)
        end
    end
end)

-- Export
exports('ToggleFreecam', ToggleFreecam)
exports('IsFreecamActive', IsFreecamActive)
exports('GetFreecamPosition', GetFreecamPosition)

print('^2[LyxPanel v4.3]^7 Elite Freecam loaded')
