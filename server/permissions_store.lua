--[[
    LyxPanel - Permission Store (DB-backed overrides)

    Implements:
    - Role permission overrides via DB (optional)
    - Individual permission overrides via DB (optional)
    - Caching + refresh helpers

    Security:
    - Actual authorization is enforced in server/main.lua (masters only).
]]

LyxPanel = LyxPanel or {}
LyxPanel.PermissionsStore = LyxPanel.PermissionsStore or {}

local Store = {
    roleOverrides = {},       -- [role] = { perms = table, updated_at = ... }
    individualOverrides = {}, -- [identifier] = { [perm] = boolean }
    lastLoad = 0
}

local function _DecodeJson(str)
    if not str then return nil end
    local ok, data = pcall(json.decode, str)
    if ok then return data end
    return nil
end

local function _EncodeJson(tbl)
    local ok, data = pcall(json.encode, tbl or {})
    return ok and data or '{}'
end

function LyxPanel.PermissionsStore.Reload()
    if not MySQL or not MySQL.Sync then return false end

    Store.roleOverrides = {}
    Store.individualOverrides = {}

    local roles = MySQL.Sync.fetchAll('SELECT role_name, permissions, updated_by, updated_at FROM lyxpanel_role_permissions', {}) or {}
    for _, r in ipairs(roles) do
        local role = tostring(r.role_name or '')
        if role ~= '' then
            Store.roleOverrides[role] = {
                perms = _DecodeJson(r.permissions) or {},
                updated_by = r.updated_by,
                updated_at = r.updated_at
            }
        end
    end

    local rows = MySQL.Sync.fetchAll('SELECT identifier, permission_name, value FROM lyxpanel_individual_permissions', {}) or {}
    for _, row in ipairs(rows) do
        local identifier = tostring(row.identifier or '')
        local perm = tostring(row.permission_name or '')
        if identifier ~= '' and perm ~= '' then
            Store.individualOverrides[identifier] = Store.individualOverrides[identifier] or {}
            Store.individualOverrides[identifier][perm] = tonumber(row.value) == 1
        end
    end

    Store.lastLoad = os.time()
    return true
end

function LyxPanel.PermissionsStore.GetRoleOverride(role)
    return Store.roleOverrides[tostring(role or '')]
end

function LyxPanel.PermissionsStore.GetIndividualOverride(identifier)
    return Store.individualOverrides[tostring(identifier or '')]
end

function LyxPanel.PermissionsStore.SetRolePermission(role, perm, value, actorName, actorIdentifier)
    role = tostring(role or '')
    perm = tostring(perm or '')
    if role == '' or perm == '' then return false end

    local current = Store.roleOverrides[role] and Store.roleOverrides[role].perms or nil
    if not current then
        current = {}
    end

    local old = current[perm]
    current[perm] = value == true

    MySQL.Sync.execute([[
        INSERT INTO lyxpanel_role_permissions (role_name, permissions, updated_by, updated_at)
        VALUES (?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE permissions = VALUES(permissions), updated_by = VALUES(updated_by), updated_at = NOW()
    ]], { role, _EncodeJson(current), tostring(actorName or 'unknown') })

    MySQL.Sync.execute([[
        INSERT INTO lyxpanel_permission_audit
        (actor_identifier, actor_name, scope, role_name, permission_name, old_value, new_value)
        VALUES (?, ?, 'role', ?, ?, ?, ?)
    ]], {
        tostring(actorIdentifier or 'unknown'),
        tostring(actorName or 'unknown'),
        role,
        perm,
        old == nil and nil or tostring(old),
        tostring(value == true)
    })

    Store.roleOverrides[role] = Store.roleOverrides[role] or {}
    Store.roleOverrides[role].perms = current
    Store.roleOverrides[role].updated_by = tostring(actorName or 'unknown')
    Store.roleOverrides[role].updated_at = os.date('%Y-%m-%d %H:%M:%S')
    return true
end

function LyxPanel.PermissionsStore.ResetRole(role, actorName, actorIdentifier)
    role = tostring(role or '')
    if role == '' then return false end

    local old = Store.roleOverrides[role] and Store.roleOverrides[role].perms or nil

    MySQL.Sync.execute('DELETE FROM lyxpanel_role_permissions WHERE role_name = ?', { role })

    MySQL.Sync.execute([[
        INSERT INTO lyxpanel_permission_audit
        (actor_identifier, actor_name, scope, role_name, permission_name, old_value, new_value)
        VALUES (?, ?, 'role', ?, '__RESET__', ?, '__DEFAULT__')
    ]], {
        tostring(actorIdentifier or 'unknown'),
        tostring(actorName or 'unknown'),
        role,
        old and _EncodeJson(old) or nil
    })

    Store.roleOverrides[role] = nil
    return true
end

function LyxPanel.PermissionsStore.SetIndividualPermission(identifier, perm, value, actorName, actorIdentifier)
    identifier = tostring(identifier or '')
    perm = tostring(perm or '')
    if identifier == '' or perm == '' then return false end

    local old = Store.individualOverrides[identifier] and Store.individualOverrides[identifier][perm] or nil
    local val = value == true

    MySQL.Sync.execute([[
        INSERT INTO lyxpanel_individual_permissions (identifier, permission_name, value, updated_by, updated_at)
        VALUES (?, ?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE value = VALUES(value), updated_by = VALUES(updated_by), updated_at = NOW()
    ]], { identifier, perm, val and 1 or 0, tostring(actorName or 'unknown') })

    MySQL.Sync.execute([[
        INSERT INTO lyxpanel_permission_audit
        (actor_identifier, actor_name, scope, target_identifier, permission_name, old_value, new_value)
        VALUES (?, ?, 'individual', ?, ?, ?, ?)
    ]], {
        tostring(actorIdentifier or 'unknown'),
        tostring(actorName or 'unknown'),
        identifier,
        perm,
        old == nil and nil or tostring(old),
        tostring(val)
    })

    Store.individualOverrides[identifier] = Store.individualOverrides[identifier] or {}
    Store.individualOverrides[identifier][perm] = val
    return true
end

function LyxPanel.PermissionsStore.ResetIndividual(identifier, perm, actorName, actorIdentifier)
    identifier = tostring(identifier or '')
    perm = tostring(perm or '')
    if identifier == '' or perm == '' then return false end

    local old = Store.individualOverrides[identifier] and Store.individualOverrides[identifier][perm] or nil
    MySQL.Sync.execute('DELETE FROM lyxpanel_individual_permissions WHERE identifier = ? AND permission_name = ?', { identifier, perm })

    MySQL.Sync.execute([[
        INSERT INTO lyxpanel_permission_audit
        (actor_identifier, actor_name, scope, target_identifier, permission_name, old_value, new_value)
        VALUES (?, ?, 'individual', ?, ?, ?, '__DEFAULT__')
    ]], {
        tostring(actorIdentifier or 'unknown'),
        tostring(actorName or 'unknown'),
        identifier,
        perm,
        old == nil and nil or tostring(old)
    })

    if Store.individualOverrides[identifier] then
        Store.individualOverrides[identifier][perm] = nil
        if next(Store.individualOverrides[identifier]) == nil then
            Store.individualOverrides[identifier] = nil
        end
    end

    return true
end

print('^2[LyxPanel]^7 permissions_store loaded')

