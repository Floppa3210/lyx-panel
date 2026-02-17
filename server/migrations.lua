--[[
    LyxPanel - Versioned DB Migrations

    Replaces ad-hoc SQL with a versioned migration runner using:
      - lyxpanel_schema_migrations
]]

LyxPanel = LyxPanel or {}
LyxPanel.Migrations = LyxPanel.Migrations or {}

local MIGRATIONS_TABLE = 'lyxpanel_schema_migrations'

local function _Exec(query, params)
    local ok, err = pcall(function()
        return MySQL.Sync.execute(query, params or {})
    end)
    if not ok then
        print(('^1[LyxPanel][MIGRATIONS]^7 Query failed: %s'):format(tostring(err)))
        return false
    end
    return true
end

local function _FetchAll(query, params)
    local ok, res = pcall(function()
        return MySQL.Sync.fetchAll(query, params or {})
    end)
    if not ok then
        print(('^1[LyxPanel][MIGRATIONS]^7 Fetch failed: %s'):format(tostring(res)))
        return nil
    end
    return res or {}
end

local function _ColumnExists(tableName, columnName)
    local rows = _FetchAll([[
        SELECT COUNT(*) AS c
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
          AND COLUMN_NAME = ?
    ]], { tableName, columnName })

    local c = rows and rows[1] and tonumber(rows[1].c) or 0
    return c > 0
end

local function _EnsureMigrationsTable()
    return _Exec(([[
        CREATE TABLE IF NOT EXISTS %s (
            version INT UNSIGNED NOT NULL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]]):format(MIGRATIONS_TABLE))
end

local function _GetAppliedVersions()
    local applied = {}
    local rows = _FetchAll(('SELECT version FROM %s'):format(MIGRATIONS_TABLE))
    for _, r in ipairs(rows or {}) do
        local v = tonumber(r.version)
        if v then applied[v] = true end
    end
    return applied
end

local function _ApplyMigration(m)
    print(('^5[LyxPanel][MIGRATIONS]^7 Applying v%d: %s'):format(m.version, m.name))

    if type(m.up) == 'function' then
        local ok, err = pcall(m.up)
        if not ok then
            print(('^1[LyxPanel][MIGRATIONS]^7 Migration v%d failed: %s'):format(m.version, tostring(err)))
            return false
        end
    elseif type(m.up) == 'table' then
        for _, q in ipairs(m.up) do
            if not _Exec(q) then
                print(('^1[LyxPanel][MIGRATIONS]^7 Migration v%d failed executing SQL'):format(m.version))
                return false
            end
        end
    else
        print(('^1[LyxPanel][MIGRATIONS]^7 Migration v%d has invalid `up`'):format(m.version))
        return false
    end

    _Exec(('INSERT IGNORE INTO %s (version, name) VALUES (?, ?)'):format(MIGRATIONS_TABLE), { m.version, m.name })
    return true
end

local function _CreateCoreTables()
    return {
        [[CREATE TABLE IF NOT EXISTS lyxpanel_reports (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            reporter_id VARCHAR(255) NOT NULL,
            reporter_name VARCHAR(100) NOT NULL,
            reported_id VARCHAR(255),
            reported_name VARCHAR(100),
            reason TEXT NOT NULL,
            priority VARCHAR(20) DEFAULT 'medium',
            status ENUM('open','in_progress','closed','rejected') DEFAULT 'open',
            assigned_to VARCHAR(255),
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_report_messages (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            report_id INT UNSIGNED NOT NULL,
            sender_id VARCHAR(255) NOT NULL,
            sender_name VARCHAR(100) NOT NULL,
            message TEXT NOT NULL,
            is_admin TINYINT(1) NOT NULL DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_report_id (report_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_logs (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            admin_id VARCHAR(255) NOT NULL,
            admin_name VARCHAR(100) NOT NULL,
            action VARCHAR(100) NOT NULL,
            target_id VARCHAR(255),
            target_name VARCHAR(100),
            details JSON,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_admin (admin_id),
            INDEX idx_action (action),
            INDEX idx_created_at (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_notes (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            target_id VARCHAR(255) NOT NULL,
            note TEXT NOT NULL,
            admin_id VARCHAR(255) NOT NULL,
            admin_name VARCHAR(100) NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_target (target_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_tickets (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            player_id VARCHAR(255) NOT NULL,
            player_name VARCHAR(100) NOT NULL,
            subject VARCHAR(255) NOT NULL,
            message TEXT NOT NULL,
            status ENUM('open','answered','closed') DEFAULT 'open',
            admin_response TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_transactions (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            player_id VARCHAR(255) NOT NULL,
            player_name VARCHAR(100) NOT NULL,
            type VARCHAR(50) NOT NULL,
            amount BIGINT NOT NULL,
            account VARCHAR(50) NOT NULL,
            admin_id VARCHAR(255) NOT NULL,
            admin_name VARCHAR(100) NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_player (player_id),
            INDEX idx_created_at (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_whitelist (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            identifier VARCHAR(255) NOT NULL,
            name VARCHAR(100) DEFAULT NULL,
            player_name VARCHAR(100) DEFAULT NULL,
            added_by VARCHAR(100) NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uniq_identifier (identifier),
            INDEX idx_created_at (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_admin_stats (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            admin_identifier VARCHAR(255) NOT NULL,
            admin_name VARCHAR(100) DEFAULT NULL,
            total_kicks INT UNSIGNED NOT NULL DEFAULT 0,
            total_bans INT UNSIGNED NOT NULL DEFAULT 0,
            total_warns INT UNSIGNED NOT NULL DEFAULT 0,
            total_reports_handled INT UNSIGNED NOT NULL DEFAULT 0,
            total_teleports INT UNSIGNED NOT NULL DEFAULT 0,
            total_spawns INT UNSIGNED NOT NULL DEFAULT 0,
            last_action DATETIME DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uniq_admin_identifier (admin_identifier),
            INDEX idx_last_action (last_action)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_teleport_favorites (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            admin_identifier VARCHAR(255) NOT NULL,
            name VARCHAR(100) NOT NULL,
            x DOUBLE NOT NULL,
            y DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            heading DOUBLE NOT NULL DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_admin (admin_identifier),
            INDEX idx_name (name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_weapon_kits (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            description TEXT DEFAULT NULL,
            weapons LONGTEXT NOT NULL,
            is_global TINYINT(1) NOT NULL DEFAULT 0,
            created_by VARCHAR(100) DEFAULT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_global (is_global),
            INDEX idx_created_by (created_by)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_outfits (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            identifier VARCHAR(255) NOT NULL,
            outfit_name VARCHAR(100) NOT NULL,
            outfit_data LONGTEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_identifier (identifier),
            INDEX idx_created_at (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        -- Used by actions_extended.lua (banIPRange)
        [[CREATE TABLE IF NOT EXISTS lyxpanel_ip_bans (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            ip_range VARCHAR(50) NOT NULL,
            reason TEXT,
            banned_by VARCHAR(100),
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            active TINYINT(1) DEFAULT 1,
            INDEX idx_active (active),
            INDEX idx_created_at (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
    }
end

local function _CreatePermissionTables()
    return {
        [[CREATE TABLE IF NOT EXISTS lyxpanel_role_permissions (
            role_name VARCHAR(64) NOT NULL PRIMARY KEY,
            permissions JSON NOT NULL,
            updated_by VARCHAR(100) DEFAULT NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_individual_permissions (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            identifier VARCHAR(255) NOT NULL,
            permission_name VARCHAR(100) NOT NULL,
            value TINYINT(1) NOT NULL DEFAULT 0,
            updated_by VARCHAR(100) DEFAULT NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uniq_identifier_perm (identifier, permission_name),
            INDEX idx_identifier (identifier)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

        [[CREATE TABLE IF NOT EXISTS lyxpanel_permission_audit (
            id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            actor_identifier VARCHAR(255) NOT NULL,
            actor_name VARCHAR(100) NOT NULL,
            scope ENUM('role','individual') NOT NULL,
            role_name VARCHAR(64) DEFAULT NULL,
            target_identifier VARCHAR(255) DEFAULT NULL,
            permission_name VARCHAR(100) NOT NULL,
            old_value VARCHAR(10) DEFAULT NULL,
            new_value VARCHAR(10) DEFAULT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_actor (actor_identifier),
            INDEX idx_created_at (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
    }
end

local function _CreateAccessTables()
    return {
        [[CREATE TABLE IF NOT EXISTS lyxpanel_access_list (
            identifier VARCHAR(255) NOT NULL PRIMARY KEY,
            group_name VARCHAR(64) NOT NULL,
            note VARCHAR(255) DEFAULT NULL,
            added_by VARCHAR(100) NOT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_group (group_name),
            INDEX idx_updated_at (updated_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
    }
end

local MIGRATIONS = {
    {
        version = 1,
        name = 'core_tables',
        up = _CreateCoreTables()
    },
    {
        version = 2,
        name = 'permissions_tables',
        up = _CreatePermissionTables()
    },
    {
        version = 3,
        name = 'logs_legacy_timestamp_compat',
        up = function()
            -- Some legacy schemas used `timestamp` instead of `created_at`.
            if not _ColumnExists('lyxpanel_logs', 'created_at') then
                _Exec('ALTER TABLE lyxpanel_logs ADD COLUMN created_at DATETIME DEFAULT CURRENT_TIMESTAMP')
            end

            if _ColumnExists('lyxpanel_logs', 'timestamp') then
                -- Best-effort backfill if created_at is NULL (shouldn't be with DEFAULT, but keep safe)
                pcall(function()
                    MySQL.Sync.execute('UPDATE lyxpanel_logs SET created_at = `timestamp` WHERE created_at IS NULL')
                end)
            end
        end
    },
    {
        version = 4,
        name = 'access_list_tables',
        up = _CreateAccessTables()
    }
}

function LyxPanel.Migrations.Apply()
    if not MySQL or not MySQL.Sync then
        print('^1[LyxPanel][MIGRATIONS]^7 MySQL not ready')
        return false
    end

    if not _EnsureMigrationsTable() then
        return false
    end

    local applied = _GetAppliedVersions()

    table.sort(MIGRATIONS, function(a, b) return a.version < b.version end)
    for _, m in ipairs(MIGRATIONS) do
        if not applied[m.version] then
            local ok = _ApplyMigration(m)
            if not ok then
                return false
            end
        end
    end

    print('^2[LyxPanel][MIGRATIONS]^7 OK')
    return true
end

print('^2[LyxPanel]^7 migrations module loaded')
