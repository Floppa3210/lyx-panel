-- ╔═══════════════════════════════════════════════════════════════════════════════╗
-- ║                    LYXPANEL v4.0 - EXTENDED DATABASE                          ║
-- ║                      Additional Tables for New Features                        ║
-- ╚═══════════════════════════════════════════════════════════════════════════════╝
--
-- Run this SQL to add new tables for extended features

-- ═══════════════════════════════════════════════════════════════════════════════
-- MISSING CORE TABLES (Fixes 'corrupted panel' issues)
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS lyxpanel_logs (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admin_id VARCHAR(100),
    admin_name VARCHAR(100),
    action VARCHAR(50),
    target_id VARCHAR(100),
    target_name VARCHAR(100),
    details JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_admin (admin_id),
    INDEX idx_target (target_id),
    INDEX idx_action (action)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Core lyxguard tables (lyxguard_detections / lyxguard_warnings) are managed by:
--   lyx-guard/database/database.sql
-- Do not redefine them here to avoid schema drift/incompatible columns.

-- Whitelist table
CREATE TABLE IF NOT EXISTS lyxpanel_whitelist (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    identifier VARCHAR(255) NOT NULL UNIQUE,
    player_name VARCHAR(100),
    added_by VARCHAR(100),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_identifier (identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- IP Bans table
CREATE TABLE IF NOT EXISTS lyxpanel_ip_bans (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ip_range VARCHAR(50) NOT NULL,
    reason TEXT,
    banned_by VARCHAR(100),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    active TINYINT(1) DEFAULT 1,
    INDEX idx_active (active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Player sessions history
CREATE TABLE IF NOT EXISTS lyxpanel_sessions (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    identifier VARCHAR(255) NOT NULL,
    player_name VARCHAR(100),
    steam VARCHAR(255),
    discord VARCHAR(255),
    license VARCHAR(255),
    ip VARCHAR(64),
    join_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    leave_time DATETIME,
    duration INT UNSIGNED DEFAULT 0,
    INDEX idx_identifier (identifier),
    INDEX idx_join_time (join_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Scheduled tasks
CREATE TABLE IF NOT EXISTS lyxpanel_scheduled_tasks (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    task_type VARCHAR(50) NOT NULL,
    task_data JSON,
    next_run DATETIME NOT NULL,
    repeat_interval INT UNSIGNED,
    created_by VARCHAR(100),
    active TINYINT(1) DEFAULT 1,
    INDEX idx_next_run (next_run),
    INDEX idx_active (active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Jail records
CREATE TABLE IF NOT EXISTS lyxpanel_jail (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    identifier VARCHAR(255) NOT NULL,
    player_name VARCHAR(100),
    reason TEXT,
    jailed_by VARCHAR(100),
    jail_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    release_time DATETIME,
    released_early TINYINT(1) DEFAULT 0,
    INDEX idx_identifier (identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Mute records
CREATE TABLE IF NOT EXISTS lyxpanel_mutes (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    identifier VARCHAR(255) NOT NULL,
    player_name VARCHAR(100),
    mute_type ENUM('chat', 'voice', 'both') DEFAULT 'chat',
    reason TEXT,
    muted_by VARCHAR(100),
    mute_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    unmute_time DATETIME,
    active TINYINT(1) DEFAULT 1,
    INDEX idx_identifier (identifier),
    INDEX idx_active (active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Admin macros/quick commands
CREATE TABLE IF NOT EXISTS lyxpanel_macros (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    actions JSON NOT NULL,
    created_by VARCHAR(100),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_global TINYINT(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Player statistics
CREATE TABLE IF NOT EXISTS lyxpanel_player_stats (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    identifier VARCHAR(255) NOT NULL UNIQUE,
    player_name VARCHAR(100),
    total_playtime INT UNSIGNED DEFAULT 0,
    total_sessions INT UNSIGNED DEFAULT 0,
    first_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
    total_warnings INT UNSIGNED DEFAULT 0,
    total_kicks INT UNSIGNED DEFAULT 0,
    total_bans INT UNSIGNED DEFAULT 0,
    INDEX idx_identifier (identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DELIMITER //

-- Trigger to update player stats on warning
DROP TRIGGER IF EXISTS update_stats_on_warning//
CREATE TRIGGER update_stats_on_warning
AFTER INSERT ON lyxguard_warnings
FOR EACH ROW
BEGIN
    INSERT INTO lyxpanel_player_stats (identifier, total_warnings)
    VALUES (NEW.identifier, 1)
    ON DUPLICATE KEY UPDATE total_warnings = total_warnings + 1;
END//

DELIMITER ;

-- ═══════════════════════════════════════════════════════════════════════════════
-- v4.5 - NEW FEATURES TABLES
-- ═══════════════════════════════════════════════════════════════════════════════

-- Teleport favorites per admin
CREATE TABLE IF NOT EXISTS lyxpanel_teleport_favorites (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admin_identifier VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    x FLOAT NOT NULL,
    y FLOAT NOT NULL,
    z FLOAT NOT NULL,
    heading FLOAT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_admin (admin_identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Weapon kits (custom, not just config)
CREATE TABLE IF NOT EXISTS lyxpanel_weapon_kits (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    weapons JSON NOT NULL,
    created_by VARCHAR(100),
    is_global TINYINT(1) DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Admin rankings/stats
CREATE TABLE IF NOT EXISTS lyxpanel_admin_stats (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admin_identifier VARCHAR(255) NOT NULL UNIQUE,
    admin_name VARCHAR(100),
    total_kicks INT UNSIGNED DEFAULT 0,
    total_bans INT UNSIGNED DEFAULT 0,
    total_warns INT UNSIGNED DEFAULT 0,
    total_reports_handled INT UNSIGNED DEFAULT 0,
    total_teleports INT UNSIGNED DEFAULT 0,
    total_spawns INT UNSIGNED DEFAULT 0,
    last_action DATETIME,
    first_action DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_admin (admin_identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Report priority tracking
SET @has_priority := (
    SELECT COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'lyxpanel_logs'
      AND COLUMN_NAME = 'priority'
);

SET @priority_sql := IF(
    @has_priority = 0,
    'ALTER TABLE lyxpanel_logs ADD COLUMN priority ENUM(''low'', ''medium'', ''high'', ''critical'') DEFAULT ''medium''',
    'SELECT 1'
);

PREPARE stmt_priority FROM @priority_sql;
EXECUTE stmt_priority;
DEALLOCATE PREPARE stmt_priority;

-- Player outfits storage
CREATE TABLE IF NOT EXISTS lyxpanel_outfits (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    identifier VARCHAR(255) NOT NULL,
    outfit_name VARCHAR(100) NOT NULL,
    outfit_data JSON NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_identifier (identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insert default weapon kits
INSERT IGNORE INTO lyxpanel_weapon_kits (name, description, weapons, is_global) VALUES
('police', 'Kit estándar de policía', '["WEAPON_PISTOL:100","WEAPON_STUNGUN:1","WEAPON_NIGHTSTICK:0","WEAPON_FLASHLIGHT:0"]', 1),
('criminal', 'Kit básico criminal', '["WEAPON_PISTOL:50","WEAPON_KNIFE:0","WEAPON_CROWBAR:0"]', 1),
('admin', 'Kit completo de admin', '["WEAPON_COMBATPISTOL:9999","WEAPON_CARBINERIFLE:9999","WEAPON_PUMPSHOTGUN:9999","WEAPON_SMG:9999"]', 1),
('swat', 'Kit SWAT/Fuerzas especiales', '["WEAPON_CARBINERIFLE:500","WEAPON_PUMPSHOTGUN:100","WEAPON_SMOKEGRENADE:5","WEAPON_FLASHBANG:5"]', 1);

SELECT 'LyxPanel v4.5 Complete Database Schema Installed' AS Status;
