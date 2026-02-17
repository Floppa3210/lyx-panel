--[[
    LyxPanel - Server Bootstrap (Security/Init Helpers)

    Goals:
    - Centralize resource-level hardening and helper utilities
    - Avoid dangerous dynamic code execution patterns (load/loadstring)
    - Provide light integration helpers for optional resources (lyx-guard)
]]

LyxPanel = LyxPanel or {}
LyxPanel.Bootstrap = LyxPanel.Bootstrap or {}

local _warnOnce = {}
local function WarnOnce(key, msg)
    if _warnOnce[key] then return end
    _warnOnce[key] = true
    print(msg)
end

-- ---------------------------------------------------------------------------
-- Hardening: block dynamic code execution inside this resource environment
-- ---------------------------------------------------------------------------

local function _BlockedDynamicCode()
    error('[LyxPanel][SECURITY] Dynamic code execution is disabled (load/loadstring).', 2)
end

-- Only override if present to avoid nil indexing surprises.
if type(_G.load) == 'function' then
    _G.load = _BlockedDynamicCode
end
if type(_G.loadstring) == 'function' then
    _G.loadstring = _BlockedDynamicCode
end
if type(_G.loadfile) == 'function' then
    _G.loadfile = _BlockedDynamicCode
end
if type(_G.dofile) == 'function' then
    _G.dofile = _BlockedDynamicCode
end

-- ---------------------------------------------------------------------------
-- ESX Helper (imports.lua should provide ESX, but keep a safe fallback)
-- ---------------------------------------------------------------------------

function LyxPanel.GetESX()
    if ESX then return ESX end
    if _G.ESX then
        ESX = _G.ESX
        return ESX
    end

    if GetResourceState('es_extended') == 'started' then
        local ok, obj = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and obj then
            ESX = obj
            _G.ESX = obj
            return ESX
        end
    end

    return nil
end

---Wait for ESX to be available (bounded).
---@param timeoutMs number|nil
---@return table|nil esx
function LyxPanel.WaitForESX(timeoutMs)
    timeoutMs = tonumber(timeoutMs) or 15000
    local deadline = GetGameTimer() + timeoutMs

    while not LyxPanel.GetESX() do
        if GetGameTimer() > deadline then
            return nil
        end
        Wait(200)
    end

    return ESX
end

CreateThread(function()
    local deadline = GetGameTimer() + 15000
    while not LyxPanel.GetESX() do
        if GetGameTimer() > deadline then
            WarnOnce('esx_timeout', '^1[LyxPanel]^7 ESX no disponible (timeout). Revisa que `es_extended` este started.')
            return
        end
        Wait(200)
    end
end)

-- ---------------------------------------------------------------------------
-- Optional integration checks
-- ---------------------------------------------------------------------------

function LyxPanel.IsResourceStarted(name)
    return GetResourceState(name) == 'started'
end

function LyxPanel.IsLyxGuardAvailable()
    if GetResourceState('lyx-guard') ~= 'started' then return false end
    if not exports['lyx-guard'] then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Optional integration: Safe-state windows for LyxGuard (reduce false positives)
-- ---------------------------------------------------------------------------

function LyxPanel.GetGuardSafeMs(key, fallback)
    local limits = Config and Config.ActionLimits or nil
    local v = limits and limits.guardSafeMs and limits.guardSafeMs[key]
    if type(v) == 'number' then
        return v
    end
    return fallback
end

function LyxPanel.TryGuardSafe(targetId, types, durationMs)
    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return false end
    if not LyxPanel.IsLyxGuardAvailable() then return false end

    local ok = pcall(function()
        exports['lyx-guard']:SetPlayerSafe(targetId, types, durationMs)
    end)
    return ok == true
end

function LyxPanel.WarnIfMissingDependency(depName, featureLabel)
    WarnOnce(('dep_%s_%s'):format(depName, featureLabel or 'feature'),
        ('^3[LyxPanel]^7 Dependencia no activa: %s. Feature deshabilitada: %s'):format(depName, featureLabel or 'N/A'))
end

CreateThread(function()
    Wait(2000)
    if not LyxPanel.IsLyxGuardAvailable() then
        WarnOnce('dep_lyxguard_boot',
            '^3[LyxPanel]^7 lyx-guard no esta iniciado. Funciones anti-cheat y sanciones avanzadas quedaran limitadas.')
    end
end)

print('^2[LyxPanel]^7 bootstrap loaded')
