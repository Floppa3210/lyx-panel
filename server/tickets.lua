--[[
    LyxPanel - Simple Ticket System (in-game, open source)

    Purpose:
    - Let players create support tickets via command.
    - Staff manages tickets from the NUI panel (assign/reply/close/reopen) via lyxpanel:action:*.

    Security notes:
    - Ticket creation is rate-limited and strictly sanitized server-side.
    - Ticket management uses the admin action firewall (token/nonce + schema + permissions).
]]

local ESX = ESX

CreateThread(function()
    local resolved = ESX
    if LyxPanel and LyxPanel.WaitForESX then
        resolved = LyxPanel.WaitForESX(15000)
    end

    if not resolved then
        print('^1[LyxPanel]^7 tickets: ESX no disponible (timeout).')
        return
    end

    ESX = resolved
    _G.ESX = _G.ESX or resolved
end)

local function _GetId(source, idType)
    idType = idType or 'license'
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, idType .. ':') then
            return id
        end
    end
    return 'unknown'
end

local function _Trim(s)
    s = tostring(s or '')
    return (s:match('^%s*(.-)%s*$') or s)
end

local _TicketCooldown = {}

local function _IsRateLimited(src, key, cooldownMs)
    if not src or src <= 0 then return true end
    cooldownMs = tonumber(cooldownMs) or 0
    if cooldownMs <= 0 then return false end

    local now = GetGameTimer()
    _TicketCooldown[src] = _TicketCooldown[src] or {}
    local last = _TicketCooldown[src][key] or 0
    if (now - last) < cooldownMs then
        return true
    end
    _TicketCooldown[src][key] = now
    return false
end

local function _SanitizeText(v, maxLen)
    maxLen = tonumber(maxLen) or 200
    v = _Trim(v)
    if v == '' then return '' end
    -- Best-effort sanitize using shared lib if present.
    if LyxPanelLib and LyxPanelLib.Sanitize then
        v = LyxPanelLib.Sanitize(v, maxLen)
    end
    v = v:sub(1, maxLen)
    return v
end

local function _GetLimitNumber(name, fallback)
    local limits = Config and Config.ActionLimits or nil
    local v = limits and limits[name]
    if type(v) == 'number' then
        return v
    end
    return fallback
end

local function _GetCooldownMs(key, fallback)
    local limits = Config and Config.ActionLimits or nil
    local v = limits and limits.cooldownMs and limits.cooldownMs[key]
    if type(v) == 'number' then
        return v
    end
    return fallback
end

local function _Notify(src, msgType, msg)
    if not src or src <= 0 then return end
    TriggerClientEvent('lyxpanel:notify', src, msgType or 'info', msg or '')
end

local function _NotifyStaff(message)
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src and src > 0 and type(HasPermission) == 'function' and HasPermission(src, 'canUseTickets') then
            _Notify(src, 'info', message)
        end
    end
end

local function _CreateTicketForPlayer(src, subject, message)
    if not MySQL or not MySQL.insert then
        return false, 'mysql_not_ready'
    end

    local cd = _GetCooldownMs('ticketCreate', 120000)
    if _IsRateLimited(src, 'ticketCreate', cd) then
        return false, 'rate_limited'
    end

    local subjectMax = _GetLimitNumber('maxTicketSubjectLength', 120)
    local messageMax = _GetLimitNumber('maxTicketMessageLength', 800)

    subject = _SanitizeText(subject, subjectMax)
    message = _SanitizeText(message, messageMax)
    if subject == '' then subject = 'Soporte' end
    if message == '' then
        return false, 'empty_message'
    end

    local identifier = _GetId(src, 'license')
    local playerName = GetPlayerName(src) or 'unknown'

    local ok, insertedId = pcall(function()
        return MySQL.insert(
            'INSERT INTO lyxpanel_tickets (player_id, player_name, subject, message) VALUES (?, ?, ?, ?)',
            { identifier, playerName, subject, message }
        )
    end)
    if not ok then
        return false, 'db_insert_failed'
    end

    local ticketId = tonumber(insertedId)
    return true, ticketId
end

-- Player command: /ticket asunto | mensaje
RegisterCommand('ticket', function(source, args, raw)
    if source == 0 then return end

    local text = tostring(raw or '')
    -- Remove command name.
    text = text:gsub('^%s*/?ticket%s*', '')
    text = _Trim(text)

    if text == '' then
        _Notify(source, 'info', 'Uso: /ticket asunto | mensaje  (tambien podes: /ticket mensaje)')
        return
    end

    local subject, message = nil, nil
    local pipe = text:find('%|', 1, true)
    if pipe then
        subject = _Trim(text:sub(1, pipe - 1))
        message = _Trim(text:sub(pipe + 1))
    else
        subject = 'Soporte'
        message = text
    end

    local ok, result = _CreateTicketForPlayer(source, subject, message)
    if not ok then
        if result == 'rate_limited' then
            _Notify(source, 'warning', 'Espera un poco antes de crear otro ticket.')
        elseif result == 'empty_message' then
            _Notify(source, 'error', 'Mensaje invalido.')
        else
            _Notify(source, 'error', 'No se pudo crear el ticket.')
        end
        return
    end

    _Notify(source, 'success', ('Ticket creado: #%s'):format(tostring(result)))
    _NotifyStaff(('Nuevo ticket #%s de %s'):format(tostring(result), GetPlayerName(source) or 'jugador'))
end, false)

print('^2[LyxPanel]^7 tickets module loaded')

