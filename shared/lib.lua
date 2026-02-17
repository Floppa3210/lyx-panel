--[[
    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                           LYXPANEL v3.0 PROFESSIONAL                         ║
    ║                        Shared Utility Library                                 ║
    ╠═══════════════════════════════════════════════════════════════════════════════╣
    ║  Author: LyxDev                                                               ║
    ║  License: Commercial                                                          ║
    ║  Purpose: Shared utilities for admin panel                                    ║
    ╚═══════════════════════════════════════════════════════════════════════════════╝
]]

---@class LyxPanelLib
LyxPanelLib = LyxPanelLib or {}

LyxPanelLib.VERSION = '3.0.0'
LyxPanelLib.RESOURCE_NAME = GetCurrentResourceName()

-- ═══════════════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════════

LyxPanelLib.ACTIONS = {
    -- Player actions
    KICK = 'kick',
    BAN = 'ban',
    WARN = 'warn',
    TELEPORT = 'teleport',
    HEAL = 'heal',
    REVIVE = 'revive',
    FREEZE = 'freeze',
    SPECTATE = 'spectate',

    -- Economy actions
    GIVE_MONEY = 'give_money',
    SET_MONEY = 'set_money',
    REMOVE_MONEY = 'remove_money',

    -- Items/Weapons
    GIVE_WEAPON = 'give_weapon',
    REMOVE_WEAPON = 'remove_weapon',
    GIVE_ITEM = 'give_item',

    -- Vehicles
    SPAWN_VEHICLE = 'spawn_vehicle',
    DELETE_VEHICLE = 'delete_vehicle',
    REPAIR_VEHICLE = 'repair_vehicle',

    -- World
    SET_WEATHER = 'set_weather',
    SET_TIME = 'set_time',

    -- Admin
    NOCLIP = 'noclip',
    GODMODE = 'godmode',
    INVISIBLE = 'invisible'
}

LyxPanelLib.LOG_TYPES = {
    INFO = 'info',
    SUCCESS = 'success',
    WARNING = 'warning',
    ERROR = 'error',
    ACTION = 'action'
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════════

---Validate player source
---@param source number
---@return boolean
function LyxPanelLib.ValidateSource(source)
    return source ~= nil and type(source) == 'number' and source > 0
end

---Validate target player
---@param targetId number
---@return boolean
function LyxPanelLib.ValidateTarget(targetId)
    return targetId ~= nil and type(targetId) == 'number' and targetId > 0 and GetPlayerName(targetId) ~= nil
end

---Sanitize string input
---@param str any
---@param maxLength? number
---@return string
function LyxPanelLib.Sanitize(str, maxLength)
    if type(str) ~= 'string' then
        return tostring(str or '')
    end

    local sanitized = str:gsub('[%c]', ''):gsub('[\n\r\t]', ' ')

    if maxLength and #sanitized > maxLength then
        sanitized = sanitized:sub(1, maxLength)
    end

    return sanitized
end

---Validate and clamp number
---@param value any
---@param min number
---@param max number
---@param default number
---@return number
function LyxPanelLib.ClampNumber(value, min, max, default)
    local num = tonumber(value)
    if not num then return default end
    return math.max(min, math.min(max, num))
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- LOGGING
-- ═══════════════════════════════════════════════════════════════════════════════

local LOG_COLORS = {
    info = '^7',
    success = '^2',
    warning = '^3',
    error = '^1',
    action = '^5'
}

---Log message to console
---@param level string
---@param message string
---@param ... any
function LyxPanelLib.Log(level, message, ...)
    local color = LOG_COLORS[level] or '^7'
    local formatted = string.format(message, ...)
    print(string.format('%s[LyxPanel %s]^7 %s', color, level:upper(), formatted))
end

function LyxPanelLib.Info(message, ...)
    LyxPanelLib.Log('info', message, ...)
end

function LyxPanelLib.Success(message, ...)
    LyxPanelLib.Log('success', message, ...)
end

function LyxPanelLib.Warn(message, ...)
    LyxPanelLib.Log('warning', message, ...)
end

function LyxPanelLib.Error(message, ...)
    LyxPanelLib.Log('error', message, ...)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- LOCALIZATION
-- ═══════════════════════════════════════════════════════════════════════════════

---Get localized string
---@param key string
---@param ... any
---@return string
function LyxPanelLib.L(key, ...)
    local locale = Config and Config.Locale or 'es'
    local locales = Config and Config.Locales or {}
    local l = locales[locale] or locales['es'] or {}

    local text = l[key] or key

    if select('#', ...) > 0 then
        local success, result = pcall(string.format, text, ...)
        return success and result or text
    end

    return text
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TABLE UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════════

---Check if value is in array
---@param array table
---@param value any
---@return boolean
function LyxPanelLib.Contains(array, value)
    if type(array) ~= 'table' then return false end
    for _, v in ipairs(array) do
        if v == value then return true end
    end
    return false
end

---Deep copy table
---@param original table
---@return table
function LyxPanelLib.DeepCopy(original)
    if type(original) ~= 'table' then return original end
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = type(v) == 'table' and LyxPanelLib.DeepCopy(v) or v
    end
    return copy
end

return LyxPanelLib
