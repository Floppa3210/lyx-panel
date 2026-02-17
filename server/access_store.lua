--[[
    LyxPanel - Access Store (DB-backed panel access list)

    Purpose:
    - Allow server owners (masters) to grant/revoke panel access without editing files.
    - Keep an in-memory cache to avoid querying MySQL on every access check.

    Notes:
    - Authorization is enforced in server/main.lua (masters only).
]]

LyxPanel = LyxPanel or {}
LyxPanel.AccessStore = LyxPanel.AccessStore or {}

local Store = {
    entries = {}, -- [identifier] = { group_name=..., note=..., added_by=..., created_at=..., updated_at=... }
    lastLoad = 0
}

local function _EncodeJson(tbl)
    local ok, data = pcall(json.encode, tbl or {})
    return ok and data or '{}'
end

function LyxPanel.AccessStore.Reload()
    if not MySQL or not MySQL.Sync then return false end

    Store.entries = {}

    local rows = MySQL.Sync.fetchAll(
        'SELECT identifier, group_name, note, added_by, created_at, updated_at FROM lyxpanel_access_list',
        {}
    ) or {}

    for _, r in ipairs(rows) do
        local identifier = tostring(r.identifier or '')
        if identifier ~= '' then
            Store.entries[identifier] = {
                group_name = tostring(r.group_name or ''),
                note = r.note,
                added_by = r.added_by,
                created_at = r.created_at,
                updated_at = r.updated_at
            }
        end
    end

    Store.lastLoad = os.time()
    return true
end

function LyxPanel.AccessStore.GetGroup(identifier)
    local e = Store.entries[tostring(identifier or '')]
    if not e then return nil end
    return e.group_name
end

function LyxPanel.AccessStore.List()
    local out = {}
    for identifier, e in pairs(Store.entries) do
        out[#out + 1] = {
            identifier = identifier,
            group_name = e.group_name,
            note = e.note,
            added_by = e.added_by,
            created_at = e.created_at,
            updated_at = e.updated_at
        }
    end
    table.sort(out, function(a, b)
        return tostring(a.group_name) < tostring(b.group_name)
    end)
    return out
end

function LyxPanel.AccessStore.Set(identifier, groupName, note, actorName, actorIdentifier)
    identifier = tostring(identifier or ''):gsub('%s+', '')
    groupName = tostring(groupName or ''):gsub('%s+', '')
    note = type(note) == 'string' and note or tostring(note or '')

    if identifier == '' or groupName == '' then return false, 'invalid_input' end
    if not MySQL or not MySQL.Sync then return false, 'mysql_not_ready' end

    local old = Store.entries[identifier] and Store.entries[identifier].group_name or nil

    MySQL.Sync.execute([[
        INSERT INTO lyxpanel_access_list (identifier, group_name, note, added_by)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE group_name = VALUES(group_name), note = VALUES(note), added_by = VALUES(added_by), updated_at = NOW()
    ]], { identifier, groupName, note ~= '' and note or nil, tostring(actorName or 'unknown') })

    -- Audit in panel logs for the audit tab.
    pcall(function()
        MySQL.Sync.execute([[
            INSERT INTO lyxpanel_logs (admin_id, admin_name, action, target_id, target_name, details)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], {
            tostring(actorIdentifier or 'unknown'),
            tostring(actorName or 'unknown'),
            old and 'ACCESS_UPDATE' or 'ACCESS_GRANT',
            identifier,
            groupName,
            _EncodeJson({ note = note, old_group = old })
        })
    end)

    Store.entries[identifier] = Store.entries[identifier] or {}
    Store.entries[identifier].group_name = groupName
    Store.entries[identifier].note = note ~= '' and note or nil
    Store.entries[identifier].added_by = tostring(actorName or 'unknown')
    Store.entries[identifier].updated_at = os.date('%Y-%m-%d %H:%M:%S')
    if not Store.entries[identifier].created_at then
        Store.entries[identifier].created_at = os.date('%Y-%m-%d %H:%M:%S')
    end

    return true
end

function LyxPanel.AccessStore.Remove(identifier, actorName, actorIdentifier)
    identifier = tostring(identifier or ''):gsub('%s+', '')
    if identifier == '' then return false, 'invalid_identifier' end
    if not MySQL or not MySQL.Sync then return false, 'mysql_not_ready' end

    local old = Store.entries[identifier]

    MySQL.Sync.execute('DELETE FROM lyxpanel_access_list WHERE identifier = ?', { identifier })

    pcall(function()
        MySQL.Sync.execute([[
            INSERT INTO lyxpanel_logs (admin_id, admin_name, action, target_id, target_name, details)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], {
            tostring(actorIdentifier or 'unknown'),
            tostring(actorName or 'unknown'),
            'ACCESS_REVOKE',
            identifier,
            old and old.group_name or nil,
            _EncodeJson({ old_group = old and old.group_name or nil, note = old and old.note or nil })
        })
    end)

    Store.entries[identifier] = nil
    return true
end

print('^2[LyxPanel]^7 access_store loaded')

