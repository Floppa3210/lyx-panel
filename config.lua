--[[
    LyxPanel v3.0 - Ultra Premium Admin Panel
    50+ FUNCIONES DE ADMINISTRACIN
]]

Config = {}

Config.Locale = 'es'
Config.Debug = false
Config.OpenCommand = 'lyxpanel'
Config.OpenKey = 'F6'
Config.RefreshInterval = 5000 -- ms

-- Runtime profile selector:
-- - 'default'
-- - 'rp_light'
-- - 'production_high_load'
-- - 'hostile'
-- Legacy aliases (mapped to production_high_load for compatibility):
-- - 'production_32'
-- - 'production_64'
-- - 'production_128'
Config.RuntimeProfile = 'default'

-- Optional profile overrides (applied at end of this file).
Config.ProfilePresets = {
    rp_light = {
        RefreshInterval = 5000,
        ActionLimits = {
            cooldownMs = {
                reportsGet = 1500,
                reportsResolve = 800,
                reportsClaim = 800
            },
            guardSafeMs = {
                entity = 10000,
                movement = 9000,
                health = 5500
            }
        },
        Security = {
            deniedCooldownMs = 5000,
            adminEventFirewall = {
                maxEventsPerWindow = 90,
                windowMs = 10000,
                maxArgs = 12,
                maxStringLen = 700,
                requireActiveSession = true,
                sessionTtlMs = 12 * 60 * 1000,
                actionSecurity = {
                    tokenTtlMs = 8 * 60 * 1000,
                    nonceTtlMs = 8 * 60 * 1000,
                    maxUsedNonces = 4096
                }
            }
        }
    },

    production_32 = {
        RefreshInterval = 4500,
        ActionLimits = {
            cooldownMs = {
                reportsGet = 1250,
                reportsResolve = 650,
                reportsClaim = 650
            }
        },
        Security = {
            deniedCooldownMs = 4000,
            adminEventFirewall = {
                maxEventsPerWindow = 110,
                windowMs = 10000,
                requireActiveSession = true,
                sessionTtlMs = 10 * 60 * 1000,
                actionSecurity = {
                    tokenTtlMs = 6 * 60 * 1000,
                    nonceTtlMs = 6 * 60 * 1000
                }
            }
        }
    },

    production_64 = {
        RefreshInterval = 3500,
        ActionLimits = {
            cooldownMs = {
                reportsGet = 1000,
                reportsResolve = 600,
                reportsClaim = 600
            },
            guardSafeMs = {
                entity = 8000,
                movement = 6500,
                health = 4000
            }
        },
        Security = {
            deniedCooldownMs = 3000,
            adminEventFirewall = {
                maxEventsPerWindow = 280,
                windowMs = 10000,
                maxArgs = 14,
                maxStringLen = 700,
                requireActiveSession = true,
                sessionTtlMs = 10 * 60 * 1000,
                actionSecurity = {
                    tokenTtlMs = 6 * 60 * 1000,
                    nonceTtlMs = 6 * 60 * 1000
                }
            }
        }
    },

    production_128 = {
        RefreshInterval = 3000,
        ActionLimits = {
            cooldownMs = {
                reportsGet = 900,
                reportsResolve = 500,
                reportsClaim = 500
            },
            guardSafeMs = {
                entity = 10000,
                movement = 8000,
                health = 5000
            }
        },
        Security = {
            deniedCooldownMs = 2500,
            adminEventFirewall = {
                maxEventsPerWindow = 420,
                windowMs = 10000,
                maxArgs = 16,
                maxStringLen = 900,
                maxTotalKeys = 700,
                requireActiveSession = true,
                sessionTtlMs = 8 * 60 * 1000,
                actionSecurity = {
                    tokenTtlMs = 5 * 60 * 1000,
                    nonceTtlMs = 5 * 60 * 1000,
                    maxUsedNonces = 8192
                }
            }
        }
    },

    hostile = {
        RefreshInterval = 2500,
        ActionLimits = {
            cooldownMs = {
                reportsGet = 750,
                reportsResolve = 450,
                reportsClaim = 450
            },
            guardSafeMs = {
                entity = 7000,
                movement = 5000,
                health = 3000
            }
        },
        Security = {
            deniedCooldownMs = 1500,
            adminEventFirewall = {
                maxEventsPerWindow = 90,
                windowMs = 7000,
                maxArgs = 8,
                maxDepth = 4,
                maxKeysPerTable = 48,
                maxTotalKeys = 240,
                maxStringLen = 320,
                requireActiveSession = true,
                sessionTtlMs = 6 * 60 * 1000,
                sessionStateFailOpen = false,
                actionSecurity = {
                    tokenTtlMs = 2 * 60 * 1000,
                    nonceTtlMs = 3 * 60 * 1000,
                    maxUsedNonces = 2048,
                    maxClockSkewMs = 120000
                }
            }
        }
    }
}

Config.ProfilePresets.production_high_load = Config.ProfilePresets.production_128
Config.ProfilePresets.production_32 = Config.ProfilePresets.production_high_load
Config.ProfilePresets.production_64 = Config.ProfilePresets.production_high_load

-- ---------------------------------------------------------------------------
-- LIMITES / RATE-LIMIT (Server-side enforcement)
-- Mover valores fuera de server/actions.lua para poder ajustar sin tocar codigo.
-- Unidades: milisegundos (ms) salvo que se indique lo contrario.
-- ---------------------------------------------------------------------------

    Config.ActionLimits = {
    -- Economia / Items / Armas
    moneyMax = 10000000,
    itemMaxCount = 100,
    weaponAmmoMax = 1000,

    -- Cooldowns por accion (ms)
    cooldownMs = {
        giveMoney = 750,
        setMoney = 750,
        removeMoney = 750,
        transferMoney = 750,
        giveWeapon = 750,
        giveAmmo = 750,
        giveItem = 750,
        removeItem = 750,
        removeWeapon = 750,
        removeAllWeapons = 1500,

        kick = 750,
        warn = 750,
        ban = 1500,
        unban = 1500,
        kill = 750,
        slap = 750,
        setJob = 1000,
        addNote = 750,
        setWeather = 1500,
        setTime = 1500,

        -- Teleport / Control
        teleportTo = 750,
        bring = 750,
        teleportCoords = 750,
        teleportMarker = 750,
        teleportBack = 750,
        revive = 750,
        reviveRadius = 12000,
        setArmor = 750,
        setHealth = 750,
        freeze = 750,
        spectate = 750,
        heal = 750,

        -- Vehiculos (actions.lua)
        spawnVehicle = 1000,
        quickSpawnWarpTune = 1500,
        deleteVehicle = 750,
        repairVehicle = 750,
        flipVehicle = 750,
        boostVehicle = 1000,
        deleteNearbyVehicles = 5000,
        cleanVehicle = 1000,
        setVehicleColor = 1000,
        tuneVehicle = 1500,
        ghostVehicle = 500,
        getVehicleInfo = 750,

        -- Admin tools toggles
        noclip = 250,
        godmode = 250,
        invisible = 250,
        speedboost = 250,
        nitro = 250,
        vehicleGodmode = 250,

        -- Chat/announce
        announce = 1500,
        privateMessage = 750,
        adminChat = 750,
        changeModel = 1500,
        screenshot = 5000,
        screenshotBatch = 12000,
        trollAction = 750,

        clearInventory = 1500,
        adminJail = 1500,
        reviveAll = 10000,
        giveMoneyAll = 15000,
        clearArea = 3000,
        clearAllDetections = 30000,
        clearLogs = 30000,

        wipePlayer = 10000,

        -- Extended actions
        banOffline = 1500,
        banIPRange = 1500,
        reduceBan = 1500,
        warnWithEscalation = 1000,
        clearWarnings = 1000,
        jail = 1000,
        unjail = 1000,
        muteChat = 1000,
        muteVoice = 1000,
        unmute = 1000,
        scheduleAnnounce = 1500,
        giveVehicle = 1500,
        deleteGarageVehicle = 1500,
        giveLicense = 1500,
        removeLicense = 1500,
        copyPosition = 500,
        addWhitelist = 1000,
        removeWhitelist = 1000,
        announcement = 1500,

        -- v4.5 (features_v45.lua)
        saveTeleportFavorite = 1000,
        deleteTeleportFavorite = 750,
        teleportToFavorite = 750,
        teleportPlayerToPlayer = 1000,
        giveWeaponKit = 750,
        importBans = 3000,
        editBan = 1500,
        bringVehicle = 1500,
        toggleVehicleDoors = 750,
        toggleVehicleEngine = 750,
        setVehicleFuel = 1000,
        freezeVehicle = 900,
        setVehicleLivery = 1000,
        setVehicleExtra = 750,
        setVehicleNeon = 750,
        setVehicleWheelSmoke = 1000,
        setVehiclePaintAdvanced = 1000,
        setVehicleXenon = 1000,
        setVehicleModkit = 1200,
        warpIntoVehicle = 1500,
        warpOutOfVehicle = 1500,
        saveOutfit = 1500,
        loadOutfit = 750,
        deleteOutfit = 750,
        reloadConfig = 5000,

        -- Reports (reports.lua + actions.lua)
        assignReport = 750,
        closeReport = 1000,
        setReportPriority = 750,
        tpToReporter = 1000,
        sendReportMessage = 750,
        sendReportTemplate = 750,
        reportsClaim = 750,
        reportsResolve = 750,
        reportsGet = 1500,

        -- Tickets (support)
        ticketAssign = 900,
        ticketReply = 1200,
        ticketClose = 1200,
        ticketReopen = 900,
        ticketCreate = 120000
    },

    -- Ventanas de "safe-state" para evitar falsos positivos en LyxGuard cuando el panel ejecuta acciones legitimas.
    -- Estas inmunidades son cortas y solo se aplican si lyx-guard esta activo.
    guardSafeMs = {
        entity = 6000,   -- Spawn/cleanup de entidades (vehiculos/objetos/peds)
        movement = 5000, -- Teleports / movimientos bruscos
        health = 3000,   -- Heal/revive/armor/health
    },

    -- Clamps / validaciones (extended + UI inputs)
    maxReasonLength = 200,
    maxPlayerNameLength = 100,
    maxOfflineBanHours = 24 * 365, -- 1 anio
    maxReduceBanHours = 24 * 365, -- 1 anio
    maxJailMinutes = 240,
    maxMuteMinutes = 240,
    maxAnnouncementLength = 250,
    maxSearchTermLength = 50,
    maxVehicleModelLength = 32,
    maxScreenshotBatchTargets = 12,
    maxPlateLength = 8,
    maxLicenseTypeLength = 64,
    maxScheduleAnnouncements = 50,
    maxScheduleDelayMinutes = 1440,
    maxScheduleRepeatMinutes = 1440,
    maxTicketSubjectLength = 120,
    maxTicketMessageLength = 800,
    maxTicketReplyLength = 900,

    -- Outfits (features_v45.lua)
    maxOutfitJsonLength = 12000,
    maxOutfitsPerPlayer = 50,

    -- Teleport back stack (server-side memory only).
    teleportBack = {
        ttlMs = 10 * 60 * 1000,
        maxEntries = 12,
        minDistance = 1.5
    }
}

-- ---------------------------------------------------------------------------
-- SECURITY AUDIT (logging/debug)
-- ---------------------------------------------------------------------------

Config.Security = {
    -- Loggear intentos de usar acciones sin permisos (suele ser cheater trigger)
    logDeniedPermissions = true,
    deniedCooldownMs = 5000,

    -- Si lyx-guard esta iniciado, registrar como deteccion (solo log, sin ban)
    forwardDeniedToLyxGuard = true,

    -- -----------------------------------------------------------------------
    -- Admin action event firewall (server-side, pre-handler)
    -- Intercepts lyxpanel:action:* in __cfx_internal:serverEventTriggered.
    -- If a player without panel access triggers admin actions => permaban.
    -- -----------------------------------------------------------------------
    adminEventFirewall = {
        enabled = true,
        actionPrefix = 'lyxpanel:action:',
        strictAllowlist = true,
        validateAllLyxpanelEvents = true, -- schema validation for non-admin lyxpanel:* events too
        schemaOnlyPrefixes = {
            'lyxpanel:reports:',
            'lyxpanel:staffcmd:',
            'lyxpanel:spectate:'
        },
        requireActiveSession = true, -- acciones admin requieren sesion activa de panel
        sessionTtlMs = 10 * 60 * 1000,
        -- If the session state provider is unavailable, default is fail-open to avoid breaking production.
        -- Set to false in hostile environments to fail-closed.
        sessionStateFailOpen = true,

        -- High enough for real admin usage; blocks only obvious spam bursts.
        maxEventsPerWindow = 240,
        windowMs = 10000,

        -- Payload sanity limits
        maxArgs = 12,
        maxDepth = 6,
        maxKeysPerTable = 96,
        maxTotalKeys = 512,
        maxStringLen = 512,

        -- Extra strict per-event schema checks for critical actions (server/event_firewall.lua).
        schemaValidation = true,

        -- Punishment for spoof from non-panel users
        permabanOnNoAccess = true,
        banDuration = 0, -- 0 = permanent
        banReason = 'Cheating detected (admin event spoof)',
        banBy = 'LyxPanel Firewall',
        punishCooldownMs = 15000,

        -- Optional UX feedback for valid admins when firewall blocks malformed payload.
        notifyPlayer = true,

        -- Session token + nonce anti-replay for every protected admin event.
        actionSecurity = {
            enabled = true,
            requireForActionEvents = true,
            requireForProtectedEvents = true,
            tokenTtlMs = 5 * 60 * 1000,
            nonceTtlMs = 5 * 60 * 1000,
            maxUsedNonces = 4096,
            maxClockSkewMs = 180000,
            contextTtlMs = 20000,
            tokenMinLen = 24,
            tokenMaxLen = 128,
            nonceMinLen = 16,
            nonceMaxLen = 128,
            correlationMinLen = 10,
            correlationMaxLen = 128
        },

        -- Optional per-event overrides/additions:
        -- allowlist = { ['lyxpanel:action:myCustomAction'] = true }
        -- schemas = { ['lyxpanel:action:myCustomAction'] = { minArgs = 1, maxArgs = 2, types = { [1] = 'number' } } }
        -- protectedEvents = {
        --   ['lyxpanel:reports:claim'] = { requiredPermission = 'canManageReports', requireActiveSession = true }
        -- }
        allowlist = {}
    },

    -- Spoofing panel-session open from a non-admin should never happen in legit flow.
    -- This is independent from adminEventFirewall and protects the session layer.
    panelSessionSpoof = {
        enabled = true,
        permaban = true,
        banDuration = 0, -- 0 = permanent
        banReason = 'Cheating detected (panel session spoof)',
        banBy = 'LyxPanel Security',
        cooldownMs = 15000,
        dropIfGuardMissing = true
    }
}

-- 
-- PERMISOS
-- 

Config.Permissions = {
    system = 'mixed',
    allowedGroups = { 'superadmin', 'admin', 'mod', 'moderator', 'helper', 'master', 'owner' },
    acePermissions = { 'lyxpanel.access', 'lyxpanel.admin' },

    aceRolePermissions = {
        { ace = 'lyxpanel.role.owner', group = 'owner' },
        { ace = 'lyxpanel.role.master', group = 'master' },
        { ace = 'lyxpanel.role.superadmin', group = 'superadmin' },
        { ace = 'lyxpanel.role.admin', group = 'admin' },
        { ace = 'lyxpanel.role.mod', group = 'mod' },
        { ace = 'lyxpanel.role.helper', group = 'helper' },
    },

    -- 
    -- v4.2 - MASTER WHITELIST (Owners del servidor)
    -- Solo estos jugadores pueden gestionar permisos individuales
    -- 
    masterWhitelist = {
        enabled = true,
        -- Lista de identifiers (license:xxxxx, steam:xxxxx, discord:xxxxx)
        masters = {
            -- Ejemplo: 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
            -- Ejemplo: 'steam:xxxxxxxxxxxxxxx',
        },
        -- Grupos que se consideran "master" automticamente
        masterGroups = { 'owner', 'master', 'superadmin' }
    },

    -- -----------------------------------------------------------------------
    -- DB Access List (panel access without editing files)
    -- Masters can manage this list from the panel UI.
    -- Table: lyxpanel_access_list
    -- -----------------------------------------------------------------------
    accessList = {
        enabled = true
    },

    -- 
    -- v4.2 - PERMISOS INDIVIDUALES POR JUGADOR
    -- Los masters pueden asignar permisos especficos a cada jugador
    -- Estos permisos OVERRIDE los permisos del grupo
    -- 
    individualPermissions = {
        enabled = true,
        -- Se guardan en base de datos: lyxpanel_individual_permissions
        -- Estructura: identifier, permission_name, value (true/false)
    },

    -- 
    -- v4.2 - ACCIONES PELIGROSAS (Requieren doble verificacin)
    -- 
    dangerousActions = {
        -- Acciones que requieren escribir "CONFIRMO"
        requireConfirmText = {
            'wipePlayer',   -- Borrar datos del jugador
            'resetEconomy', -- Resetear economa
            'clearAllBans', -- Limpiar todos los bans
            'clearAllDetections',
            'clearLogs',
        },
        -- Acciones que requieren doble confirmacin
        requireDoubleConfirm = {
            'wipePlayer',
            'banPermanent',
            'resetEconomy',
            'reviveRadius',
        },
        -- Texto que debe escribirse para confirmar
        confirmationText = 'CONFIRMO',
        -- Tiempo minimo entre acciones peligrosas (segundos)
        cooldown = 30,
        -- Si esta activo, requiere aprobacion de un segundo admin para acciones en requireDoubleConfirm.
        enforceSecondAdmin = false,
        approvalTtlSeconds = 120,
        -- Bloqueo horario opcional para acciones peligrosas.
        -- Si startHour > endHour, se interpreta ventana que cruza medianoche.
        allowedWindow = {
            enabled = false,
            useUtc = false,
            startHour = 0,
            endHour = 23
        },
        -- Notificar a otros admins aptos cuando haya una accion esperando aprobacion.
        notifyAllAdmins = true
    },

    rolePermissions = {
        ['superadmin'] = {
            -- Jugadores bsico
            canKick = true,
            canBan = true,
            canWipePlayer = true, -- Accion peligrosa: wipe de datos
            canWarn = true,
            canGoto = true,
            canBring = true,
            canTeleport = true,
            canHeal = true,
            canRevive = true,
            canGiveArmor = true,
            canFreeze = true,
            canSpectate = true,
            canKill = true,
            canSlap = true,
            canTroll = true, -- Trolls permitidos para superadmin

            -- Economa
            canGiveMoney = true,
            canSetMoney = true,
            canTransferMoney = true,
            canViewTransactions = true,
            canEditBankAccounts = true,
            canGiveFactionMoney = true,
            canCreateCheque = true,
            canResetEconomy = true,

            -- Armas e items
            canGiveWeapons = true,
            canRemoveWeapons = true,
            canGiveItems = true,
            canRemoveItems = true,
            canClearInventory = true,
            canViewInventory = true,
            canEditInventory = true,

            -- Vehiculos
            canSpawnVehicles = true,
            canDeleteVehicle = true,
            canRepairVehicle = true,
            canViewGarage = true,
            canEditVehicle = true,
            -- Presets (self + vehicle builds/favorites/history)
            canManagePresets = true,
            canFlipVehicle = true,
            canBoostVehicle = true,
            canSpawnWithMods = true,
            canDeleteNearby = true,

            -- Trabajos y facciones
            canSetJob = true,
            canViewFaction = true,
            canKickFaction = true,
            canPromoteFaction = true,
            canCreateTempJob = true,

            -- Mundo
            canChangeWeather = true,
            canChangeTime = true,
            canSpawnObject = true,
            canDeleteObjects = true,
            canSpawnNPC = true,
            canCreateCheckpoint = true,

            -- Comunicacin
            canPrivateChat = true,
            canAnnounce = true,
            canCustomNotify = true,
            canWelcomeBanner = true,
            canMaintenanceMsg = true,
            canUseTickets = true,
            canManageTickets = true,
            canAdminChat = true,

            -- Jugador info
            canViewIPs = true,
            canViewLinkedAccounts = true,
            canAddNotes = true,
            canViewNotes = true,
            canSetVIP = true,
            canChangeName = true,
            canChangeModel = true,
            canScreenshot = true,
            canViewInventoryVisual = true,
            canViewStats = true,

            -- Reportes y logs
            canViewLogs = true,
            canManageBans = true,
            canManageReports = true,
            canAssignReport = true,
            canPriorityReport = true,

            -- Admin tools
            canNoclip = true,
            canGodmode = true,
            canInvisible = true,
            canEditConfig = true,

            -- UI
            canChangeTheme = true,
            canCustomizeUI = true,
            canViewMinimap = true,

            -- SERVER CONTROL - REMOVED FOR SECURITY
            -- canRestartServer, canKickAll, canManageResources, canExecuteCommands
            -- have been removed. Use txAdmin for server management.

            -- ADVANCED BANS (v4.0 Extended)
            canBanOffline = true,
            canBanIP = true,
            canClearWarnings = true,

            -- JAIL & MUTE (v4.0 Extended)
            canJail = true,
            canMute = true,

            -- WHITELIST (v4.0 Extended)
            canManageWhitelist = true,

            -- HISTORY (v4.0 Extended)
            canViewHistory = true,

            -- GARAGE & LICENSES (v4.0 Extended)
            canGiveVehicle = true,
            canViewLicenses = true,
            canGiveLicense = true,
            canRemoveLicense = true,
            canTroll = true
        },

        ['admin'] = {
            canKick = true,
            canBan = true,
            canWarn = true,
            canGoto = true,
            canBring = true,
            canTeleport = true,
            canHeal = true,
            canRevive = true,
            canGiveArmor = true,
            canFreeze = true,
            canSpectate = true,
            canGiveMoney = true,
            canSetMoney = false,
            canTransferMoney = false,
            canGiveWeapons = true,
            canRemoveWeapons = true,
            canGiveItems = true,
            canClearInventory = true,
            canViewInventory = true,
            canSpawnVehicles = true,
            canDeleteVehicle = true,
            canRepairVehicle = true,
            canViewGarage = true,
            canEditVehicle = true,
            canManagePresets = true,
            canFlipVehicle = true,
            canSetJob = false,
            canViewFaction = true,
            canAnnounce = true,
            canPrivateChat = true,
            canUseTickets = true,
            canManageTickets = true,
            canViewLogs = true,
            canManageBans = true,
            canManageReports = true,
            canNoclip = true,
            canGodmode = true,
            canInvisible = true,
            canScreenshot = true,
            canViewStats = true
        },
        ['mod'] = {
            canKick = true,
            canBan = false,
            canWarn = true,
            canGoto = true,
            canBring = true,
            canTeleport = true,
            canHeal = true,
            canRevive = true,
            canFreeze = true,
            canSpectate = true,
            canViewLogs = true,
            canUseTickets = true,
            canManageBans = true,
            canManageReports = true,
            canNoclip = true,
            canScreenshot = true
        },
        ['moderator'] = {
            canKick = true,
            canWarn = true,
            canGoto = true,
            canBring = true,
            canHeal = true,
            canRevive = true,
            canSpectate = true,
            canUseTickets = true,
            canManageReports = true
        },
        ['helper'] = {
            canGoto = true,
            canBring = true,
            canHeal = true,
            canSpectate = true,
            canManageReports = true
        },
        -- Master/Owner tiene TODO (hereda de superadmin pero con acceso garantizado)
        ['master'] = {
            canKick = true,
            canBan = true,
            canWipePlayer = true,
            canWarn = true,
            canGoto = true,
            canBring = true,
            canTeleport = true,
            canHeal = true,
            canRevive = true,
            canGiveArmor = true,
            canFreeze = true,
            canSpectate = true,
            canGiveMoney = true,
            canSetMoney = true,
            canTransferMoney = true,
            canViewTransactions = true,
            canEditBankAccounts = true,
            canGiveFactionMoney = true,
            canCreateCheque = true,
            canResetEconomy = true,
            canGiveWeapons = true,
            canRemoveWeapons = true,
            canGiveItems = true,
            canRemoveItems = true,
            canClearInventory = true,
            canViewInventory = true,
            canEditInventory = true,
            canSpawnVehicles = true,
            canDeleteVehicle = true,
            canRepairVehicle = true,
            canViewGarage = true,
            canEditVehicle = true,
            canManagePresets = true,
            canFlipVehicle = true,
            canBoostVehicle = true,
            canSpawnWithMods = true,
            canDeleteNearby = true,
            canSetJob = true,
            canViewFaction = true,
            canKickFaction = true,
            canPromoteFaction = true,
            canCreateTempJob = true,
            canChangeWeather = true,
            canChangeTime = true,
            canSpawnObject = true,
            canDeleteObjects = true,
            canSpawnNPC = true,
            canAnnounce = true,
            canPrivateChat = true,
            canAdminChat = true,
            canMegaphone = true,
            canUseTickets = true,
            canManageTickets = true,
            canViewLogs = true,
            canPurgeLogs = true,
            canManageBans = true,
            canManageReports = true,
            canNoclip = true,
            canGodmode = true,
            canInvisible = true,
            canUnlimitedAmmo = true,
            canMagicBullets = true,
            canServerStats = true,
            canRestartResource = true,
            canStopResource = true,
            canExecCommand = true,
            canFreezeServer = true,
            canBanIP = true,
            canClearWarnings = true,
            canJail = true,
            canMute = true,
            canManageWhitelist = true,
            canViewHistory = true,
            canGiveVehicle = true,
            canViewLicenses = true,
            canGiveLicense = true,
            canRemoveLicense = true,
            canScreenshot = true,
            canTroll = true
        },
        ['owner'] = {
            canKick = true,
            canBan = true,
            canWipePlayer = true,
            canWarn = true,
            canGoto = true,
            canBring = true,
            canTeleport = true,
            canHeal = true,
            canRevive = true,
            canGiveArmor = true,
            canFreeze = true,
            canSpectate = true,
            canGiveMoney = true,
            canSetMoney = true,
            canTransferMoney = true,
            canViewTransactions = true,
            canEditBankAccounts = true,
            canGiveFactionMoney = true,
            canCreateCheque = true,
            canResetEconomy = true,
            canGiveWeapons = true,
            canRemoveWeapons = true,
            canGiveItems = true,
            canRemoveItems = true,
            canClearInventory = true,
            canViewInventory = true,
            canEditInventory = true,
            canSpawnVehicles = true,
            canDeleteVehicle = true,
            canRepairVehicle = true,
            canViewGarage = true,
            canEditVehicle = true,
            canManagePresets = true,
            canFlipVehicle = true,
            canBoostVehicle = true,
            canSpawnWithMods = true,
            canDeleteNearby = true,
            canSetJob = true,
            canViewFaction = true,
            canKickFaction = true,
            canPromoteFaction = true,
            canCreateTempJob = true,
            canChangeWeather = true,
            canChangeTime = true,
            canSpawnObject = true,
            canDeleteObjects = true,
            canSpawnNPC = true,
            canAnnounce = true,
            canPrivateChat = true,
            canUseTickets = true,
            canManageTickets = true,
            canAdminChat = true,
            canMegaphone = true,
            canViewLogs = true,
            canPurgeLogs = true,
            canManageBans = true,
            canManageReports = true,
            canNoclip = true,
            canGodmode = true,
            canInvisible = true,
            canUnlimitedAmmo = true,
            canMagicBullets = true,
            canServerStats = true,
            canRestartResource = true,
            canStopResource = true,
            canExecCommand = true,
            canFreezeServer = true,
            canBanIP = true,
            canClearWarnings = true,
            canJail = true,
            canMute = true,
            canManageWhitelist = true,
            canViewHistory = true,
            canGiveVehicle = true,
            canViewLicenses = true,
            canGiveLicense = true,
            canRemoveLicense = true,
            canScreenshot = true,
            canTroll = true
        }
    }
}

-- 
-- DISCORD
-- 

Config.Discord = {
    enabled = true,
    webhooks = {
        adminActions =
        '',
        reports =
        '',
        tickets =
        '',
        logs =
        ''
    },
    serverName = 'LudopatiaRP',
    serverLogo = ''
}

-- 
-- MUNDO
-- 

Config.Weather = {
    types = { 'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'RAIN', 'THUNDER', 'CLEARING', 'NEUTRAL', 'SNOW', 'BLIZZARD', 'SNOWLIGHT', 'XMAS', 'HALLOWEEN', 'FOGGY', 'SMOG' }
}

Config.SpawnPoints = {
    { name = 'Hospital LS',  x = 311.7,   y = -1370.5, z = 31.5 },
    { name = 'Comisara LS', x = 441.0,   y = -982.0,  z = 30.7 },
    { name = 'Ayuntamiento', x = -544.0,  y = -204.0,  z = 38.2 },
    { name = 'Aeropuerto',   x = -1037.0, y = -2737.0, z = 20.2 },
    { name = 'Sandy Shores', x = 1827.0,  y = 3693.0,  z = 34.3 },
    { name = 'Paleto Bay',   x = -379.0,  y = 6118.0,  z = 31.5 }
}

-- 
-- ARMAS (CATEGORIZADO)
-- 

Config.Weapons = {
    {
        category = 'Pistolas',
        items = {
            { name = 'WEAPON_PISTOL',        label = 'Pistola' },
            { name = 'WEAPON_PISTOL_MK2',    label = 'Pistola MK2' },
            { name = 'WEAPON_COMBATPISTOL',  label = 'Pistola Combate' },
            { name = 'WEAPON_APPISTOL',      label = 'Pistola AP' },
            { name = 'WEAPON_STUNGUN',       label = 'Taser' },
            { name = 'WEAPON_HEAVYPISTOL',   label = 'Pistola Pesada' },
            { name = 'WEAPON_REVOLVER',      label = 'Revlver' },
            { name = 'WEAPON_CERAMICPISTOL', label = 'Pistola Cermica' }
        }
    },
    {
        category = 'SMGs',
        items = {
            { name = 'WEAPON_MICROSMG',      label = 'Micro SMG' },
            { name = 'WEAPON_SMG',           label = 'SMG' },
            { name = 'WEAPON_SMG_MK2',       label = 'SMG MK2' },
            { name = 'WEAPON_ASSAULTSMG',    label = 'SMG Asalto' },
            { name = 'WEAPON_COMBATPDW',     label = 'Combat PDW' },
            { name = 'WEAPON_MACHINEPISTOL', label = 'Pistola Ametralladora' }
        }
    },
    {
        category = 'Rifles',
        items = {
            { name = 'WEAPON_ASSAULTRIFLE',     label = 'Rifle Asalto' },
            { name = 'WEAPON_ASSAULTRIFLE_MK2', label = 'Rifle MK2' },
            { name = 'WEAPON_CARBINERIFLE',     label = 'Carabina' },
            { name = 'WEAPON_CARBINERIFLE_MK2', label = 'Carabina MK2' },
            { name = 'WEAPON_ADVANCEDRIFLE',    label = 'Rifle Avanzado' },
            { name = 'WEAPON_SPECIALCARBINE',   label = 'Carabina Especial' },
            { name = 'WEAPON_TACTICALRIFLE',    label = 'Rifle Tctico' }
        }
    },
    {
        category = 'Escopetas',
        items = {
            { name = 'WEAPON_PUMPSHOTGUN',     label = 'Escopeta Bombeo' },
            { name = 'WEAPON_PUMPSHOTGUN_MK2', label = 'Escopeta MK2' },
            { name = 'WEAPON_SAWNOFFSHOTGUN',  label = 'Escopeta Recortada' },
            { name = 'WEAPON_ASSAULTSHOTGUN',  label = 'Escopeta Asalto' },
            { name = 'WEAPON_COMBATSHOTGUN',   label = 'Escopeta Combate' }
        }
    },
    {
        category = 'Francotiradores',
        items = {
            { name = 'WEAPON_SNIPERRIFLE',     label = 'Sniper' },
            { name = 'WEAPON_HEAVYSNIPER',     label = 'Sniper Pesado' },
            { name = 'WEAPON_HEAVYSNIPER_MK2', label = 'Sniper MK2' },
            { name = 'WEAPON_MARKSMANRIFLE',   label = 'Rifle Precisin' }
        }
    },
    {
        category = 'Ametralladoras',
        items = {
            { name = 'WEAPON_MG',           label = 'Ametralladora' },
            { name = 'WEAPON_COMBATMG',     label = 'Ametralladora Combate' },
            { name = 'WEAPON_COMBATMG_MK2', label = 'Ametralladora MK2' }
        }
    },
    {
        category = 'Cuerpo a Cuerpo',
        items = {
            { name = 'WEAPON_KNIFE',      label = 'Cuchillo' },
            { name = 'WEAPON_NIGHTSTICK', label = 'Porra' },
            { name = 'WEAPON_HAMMER',     label = 'Martillo' },
            { name = 'WEAPON_BAT',        label = 'Bate' },
            { name = 'WEAPON_MACHETE',    label = 'Machete' },
            { name = 'WEAPON_KATANA',     label = 'Katana' }
        }
    },
    {
        category = 'Lanzadores',
        items = {
            { name = 'WEAPON_GRENADELAUNCHER', label = 'Lanzagranadas' },
            { name = 'WEAPON_RPG',             label = 'RPG' },
            { name = 'WEAPON_MINIGUN',         label = 'Minigun' },
            { name = 'WEAPON_RAILGUN',         label = 'Railgun' }
        }
    },
    {
        category = 'Explosivos',
        items = {
            { name = 'WEAPON_GRENADE',      label = 'Granada' },
            { name = 'WEAPON_MOLOTOV',      label = 'Molotov' },
            { name = 'WEAPON_STICKYBOMB',   label = 'Bomba Pegajosa' },
            { name = 'WEAPON_SMOKEGRENADE', label = 'Granada Humo' }
        }
    }
}

-- 
-- VEHCULOS (CATEGORIZADO)
-- 

Config.Vehicles = {
    { category = 'Super',        vehicles = { 'adder', 'autarch', 'banshee2', 'bullet', 'cheetah', 'entityxf', 'emerus', 'fmj', 'krieger', 'osiris', 't20', 'tezeract', 'turismor', 'tyrant', 'vagner', 'xa21', 'zentorno' } },
    { category = 'Sports',       vehicles = { 'alpha', 'banshee', 'carbonizzare', 'comet2', 'elegy', 'elegy2', 'feltzer2', 'jester', 'jester2', 'kuruma', 'kuruma2', 'lynx', 'massacro', 'neon', 'pariah', 'rapidgt', 'sultan', 'surano' } },
    { category = 'Muscle',       vehicles = { 'blade', 'dominator', 'dominator2', 'dukes', 'ellie', 'gauntlet', 'gauntlet2', 'hotknife', 'impaler', 'phoenix', 'ruiner', 'sabregt', 'tampa', 'vigero', 'virgo', 'voodoo' } },
    { category = 'SUVs',         vehicles = { 'baller', 'baller2', 'cavalcade', 'contender', 'dubsta', 'fq2', 'granger', 'gresley', 'habanero', 'huntley', 'landstalker', 'mesa', 'patriot', 'radi', 'rocoto', 'serrano', 'xls' } },
    { category = 'Sedans',       vehicles = { 'asea', 'asterope', 'cog55', 'cognoscenti', 'emperor', 'fugitive', 'glendale', 'ingot', 'intruder', 'premier', 'primo', 'regina', 'schafter2', 'stanier', 'stratum', 'superd', 'tailgater', 'warrener', 'washington' } },
    { category = 'Motocicletas', vehicles = { 'akuma', 'avarus', 'bagger', 'bati', 'bati2', 'bf400', 'carbonrs', 'daemon', 'double', 'hakuchou', 'hakuchou2', 'hexer', 'lectro', 'nemesis', 'oppressor', 'oppressor2', 'pcj', 'sanchez', 'shotaro' } },
    { category = 'Emergencia',   vehicles = { 'ambulance', 'fbi', 'fbi2', 'firetruk', 'police', 'police2', 'police3', 'police4', 'policeb', 'polmav', 'sheriff', 'sheriff2' } },
    { category = 'Militar',      vehicles = { 'apc', 'barracks', 'barrage', 'crusader', 'halftrack', 'insurgent', 'insurgent2', 'khanjali', 'rhino', 'scarab' } },
    { category = 'Areo',        vehicles = { 'akula', 'annihilator', 'besra', 'buzzard', 'cargobob', 'havok', 'hunter', 'hydra', 'lazer', 'maverick', 'savage', 'valkyrie', 'volatol' } },
    { category = 'Barcos',       vehicles = { 'dinghy', 'jetmax', 'marquis', 'predator', 'seashark', 'speeder', 'squalo', 'tropic', 'tug' } }
}

-- 
-- VEHCULOS PERSONALIZADOS (Auto-detectados de [cars])
-- 

-- Nombre de la carpeta de recursos que contiene tus autos personalizados
-- Ejemplo: si tienes "[cars]" en resources, pon "[cars]"
-- Si tienes mltiples carpetas, agrgalas a la lista
Config.CustomVehicleFolders = {
    '[cars]', -- Carpeta principal de autos personalizados
    -- '[vehiculos]', -- Puedes agregar ms carpetas aqu
}

-- Lista de vehiculos personalizados (se llenar automticamente al iniciar)
-- Tambin puedes agregar manualmente si quieres
Config.CustomVehicles = {
    -- Se llenar automticamente al detectar recursos en las carpetas configuradas
    -- O puedes agregar manualmente as:
    -- { name = 'nombre_spawn', label = 'Nombre Visible' },
}


-- 
-- ITEMS COMUNES (para dar items)
-- 

Config.CommonItems = {
    { name = 'bread',    label = 'Pan' },
    { name = 'water',    label = 'Agua' },
    { name = 'bandage',  label = 'Vendas' },
    { name = 'medikit',  label = 'Botiqun' },
    { name = 'phone',    label = 'Telfono' },
    { name = 'radio',    label = 'Radio' },
    { name = 'lockpick', label = 'Ganza' },
    { name = 'fixkit',   label = 'Kit Reparacin' },
    { name = 'carokit',  label = 'Kit Carrocera' },
    { name = 'armor',    label = 'Chaleco' },
    { name = 'joint',    label = 'Porro' },
    { name = 'coke',     label = 'Cocana' },
    { name = 'meth',     label = 'Meta' }
}

-- 
-- MODS DE VEHCULO
-- 

Config.VehicleMods = {
    { id = 11, name = 'Motor',       max = 4 },
    { id = 12, name = 'Frenos',      max = 3 },
    { id = 13, name = 'Transmisin', max = 3 },
    { id = 14, name = 'Bocina',      max = 58 },
    { id = 15, name = 'Suspensin',  max = 4 },
    { id = 16, name = 'Blindaje',    max = 5 },
    { id = 18, name = 'Turbo',       max = 1 },
    { id = 22, name = 'Xenon',       max = 1 }
}

-- 
-- PRIORIDADES DE REPORTE
-- 

Config.ReportPriorities = {
    { id = 'low',      label = 'Baja',    color = '#22c55e' },
    { id = 'medium',   label = 'Media',   color = '#eab308' },
    { id = 'high',     label = 'Alta',    color = '#f97316' },
    { id = 'critical', label = 'Crtica', color = '#ef4444' }
}

-- 
-- TEMPLATES DE RESPUESTA
-- 

Config.ResponseTemplates = {
    { id = 'investigating', text = 'Estamos investigando tu reporte. Un admin se pondr en contacto contigo.' },
    { id = 'resolved',      text = 'Tu reporte ha sido resuelto. Gracias por reportar.' },
    { id = 'no_evidence',   text = 'No hemos encontrado evidencia suficiente. Por favor proporciona mas detalles.' },
    { id = 'banned',        text = 'El jugador reportado ha sido sancionado. Gracias por tu ayuda.' },
    { id = 'false_report',  text = 'Este reporte ha sido determinado como falso.' }
}

-- 
-- UI THEMES
-- 

Config.Themes = {
    { id = 'dark',   name = 'Oscuro',  primary = '#4f8fff', bg = '#0a0a0f' },
    { id = 'light',  name = 'Claro',   primary = '#3b82f6', bg = '#f0f0f5' },
    { id = 'purple', name = 'Prpura', primary = '#a855f7', bg = '#0f0a15' },
    { id = 'red',    name = 'Rojo',    primary = '#ef4444', bg = '#0f0a0a' },
    { id = 'green',  name = 'Verde',   primary = '#22c55e', bg = '#0a0f0a' },
    { id = 'cyan',   name = 'Cian',    primary = '#06b6d4', bg = '#0a0f0f' }
}

-- 
-- MENSAJES
-- 

Config.Locales = {
    ['es'] = {
        no_permission = 'No tienes permiso para esto.',
        player_not_found = 'Jugador no encontrado.',
        action_success = 'Accin completada.',
        action_failed = 'Error al ejecutar.',
        ban_success = 'Jugador baneado.',
        kick_success = 'Jugador expulsado.',
        money_given = 'Dinero entregado: $%s',
        weapon_given = 'Arma entregada.',
        vehicle_spawned = 'Vehiculo spawneado.',
        teleported = 'Teleportado.',
        healed = 'Curado.',
        revived = 'Revivido.',
        frozen = 'Jugador congelado.',
        unfrozen = 'Jugador descongelado.',
        -- Staff Commands
        revive_radio_success = 'Revividos %d jugadores en un radio de %d metros.',
        revive_radio_none = 'No hay jugadores muertos en el radio.',
        revive_radio_notify = 'Has sido revivido por un admin.',
        instant_respawn_on = 'Respawn instantneo ACTIVADO.',
        instant_respawn_off = 'Respawn instantneo DESACTIVADO.',
        infinite_bullets_on = 'Municion infinita ACTIVADA.',
        infinite_bullets_off = 'Municion infinita DESACTIVADA.'
    }
}

-- 
-- COMANDOS DE STAFF
-- 

Config.StaffCommands = {
    -- 
    -- STAFF REVIVE: Presionar E cuando muerto para revivir (SOLO ADMINS)
    -- No es un comando, es automtico al presionar E cuando estas muerto
    -- Si eres admin: revivis | Si no eres admin: no pasa nada
    -- 
    staffRevive = {
        enabled = true,
        logToConsole = true,
        -- ACE permission (txAdmin, consola, etc)
        acePermission = 'lyxpanel.revive',
        -- Grupos ESX permitidos
        allowedGroups = { 'superadmin', 'admin', 'master', 'owner' }
    },

    -- 
    -- INFINITE BULLETS: Municion infinita
    -- Uso: /infinitebullets on/off
    -- 
    infiniteBullets = {
        enabled = true,
        command = 'infinitebullets',
        logToConsole = true,
        acePermission = 'lyxpanel.infinitebullets',
        allowedGroups = { 'superadmin', 'admin', 'master', 'owner' }
    }
}

-- 
-- FUNCIONES TROLL (14 opciones)
-- Configuracion individual para cada funcin de trolleo
-- 

Config.TrollFunctions = {
    -- Habilitado globalmente
    enabled = true,

    -- Loggear todas las acciones de troll (Discord webhook)
    logActions = true,

    -- Cooldown entre acciones troll (ms)
    cooldown = 3000,

    --  CONFIGURACIN INDIVIDUAL 

    explode = {
        enabled = true,
        damage = false,     -- Sin dao real
        explosionType = 29, -- Tipo de explosin visual
        cameraShake = 0.5   -- Intensidad de shake
    },

    fire = {
        enabled = true,
        duration = 8000, -- Duracion del fuego (ms)
        damage = true,   -- Causar dao real
        intensity = 3    -- Cantidad de fuegos
    },

    launch = {
        enabled = true,
        force = 50.0,       -- Fuerza del lanzamiento
        height = 30.0,      -- Altura mxima
        ragdollAfter = true -- Hacer ragdoll despus
    },

    ragdoll = {
        enabled = true,
        duration = 5000, -- Duracion del ragdoll (ms)
        type = 1         -- Tipo de ragdoll
    },

    drunk = {
        enabled = true,
        duration = 30000, -- Duracion del efecto (ms)
        intensity = 100.0 -- Intensidad (1-100)
    },

    drug = {
        enabled = true,
        duration = 20000,                 -- Duracion del efecto (ms)
        effect = 'DrugsTrevorClownsFight' -- Efecto de drogas
    },

    blackscreen = {
        enabled = true,
        duration = 10000, -- Duracion pantalla negra (ms)
        fadeSpeed = 1000  -- Velocidad de fade
    },

    scream = {
        enabled = true,
        sound = 'Scream_1',  -- Sonido a reproducir
        shakeCamera = true,  -- Sacudir cmara
        shakeDuration = 2000 -- Duracion del shake
    },

    randomtp = {
        enabled = true,
        minDistance = 500,  -- Distancia mnima
        maxDistance = 3000, -- Distancia mxima
        safeHeight = true   -- Asegurar altura segura
    },

    strip = {
        enabled = true,
        resetToDefault = true -- Resetear a modelo base
    },

    invert = {
        enabled = true,
        duration = 30000, -- Duracion controles invertidos (ms)
        invertX = true,   -- Invertir eje X
        invertY = true    -- Invertir eje Y
    },

    randomped = {
        enabled = true,
        duration = 60000,   -- Duracion del cambio (ms)
        revertAfter = true, -- Revertir despus
        allowedPeds = {     -- Peds permitidos
            'a_m_m_farmer_01', 'a_m_m_salton_02', 'a_f_m_bevhills_01',
            'a_m_m_business_01', 'a_f_y_tourist_01', 'a_m_y_hipster_01'
        }
    },

    chicken = {
        enabled = true,
        duration = 60000,     -- Duracion como pollo (ms)
        revertAfter = true,   -- Revertir despus
        model = 'a_c_chicken' -- Modelo de pollo
    },

    dance = {
        enabled = true,
        duration = 30000,                -- Duracion del baile (ms)
        animation = 'missfbi5leadinout', -- Animacin
        animDict = 'mp_pd_move_dance_01' -- Diccionario
    }
}

-- 
-- LISTA DE FUNCIONES TROLL PARA UI
-- 

Config.TrollActions = {
    { id = 'troll_explode', label = ' Explosin', icon = 'bomb' },
    { id = 'troll_fire', label = ' Fuego', icon = 'fire' },
    { id = 'troll_launch', label = ' Lanzar al Aire', icon = 'rocket' },
    { id = 'troll_ragdoll', label = ' Ragdoll', icon = 'person-falling' },
    { id = 'troll_drunk', label = ' Borracho', icon = 'wine-glass' },
    { id = 'troll_drug', label = ' Pantalla Drogas', icon = 'pills' },
    { id = 'troll_blackscreen', label = ' Pantalla Negra', icon = 'rectangle' },
    { id = 'troll_scream', label = ' Susto', icon = 'ghost' },
    { id = 'troll_randomtp', label = ' TP Aleatorio', icon = 'location-dot' },
    { id = 'troll_strip', label = ' Quitar Ropa', icon = 'shirt' },
    { id = 'troll_invert', label = ' Invertir Controles', icon = 'arrows-rotate' },
    { id = 'troll_randomped', label = ' Ped Aleatorio', icon = 'masks-theater' },
    { id = 'troll_chicken', label = ' Convertir en Pollo', icon = 'kiwi-bird' },
    { id = 'troll_dance', label = ' Hacer Bailar', icon = 'music' }
}

-- 
-- v4.5 - WEAPON KITS (Kits de armas predefinidos)
-- 

Config.WeaponKits = {
    enabled = true,
    -- Los kits se cargan de la base de datos pero tambin hay predefinidos aqu
    presets = {
        ['police'] = {
            label = ' Kit Polica',
            description = 'Equipamiento estandar de polica',
            weapons = {
                { weapon = 'WEAPON_PISTOL', ammo = 100 },
                { weapon = 'WEAPON_STUNGUN', ammo = 1 },
                { weapon = 'WEAPON_NIGHTSTICK', ammo = 0 },
                { weapon = 'WEAPON_FLASHLIGHT', ammo = 0 }
            }
        },
        ['criminal'] = {
            label = ' Kit Criminal',
            description = 'Equipamiento bsico criminal',
            weapons = {
                { weapon = 'WEAPON_PISTOL', ammo = 50 },
                { weapon = 'WEAPON_KNIFE', ammo = 0 },
                { weapon = 'WEAPON_CROWBAR', ammo = 0 }
            }
        },
        ['admin'] = {
            label = ' Kit Admin',
            description = 'Equipamiento completo de administrador',
            weapons = {
                { weapon = 'WEAPON_COMBATPISTOL', ammo = 9999 },
                { weapon = 'WEAPON_CARBINERIFLE', ammo = 9999 },
                { weapon = 'WEAPON_PUMPSHOTGUN', ammo = 9999 },
                { weapon = 'WEAPON_SMG', ammo = 9999 },
                { weapon = 'WEAPON_STUNGUN', ammo = 9999 }
            }
        },
        ['swat'] = {
            label = ' Kit SWAT',
            description = 'Fuerzas especiales',
            weapons = {
                { weapon = 'WEAPON_CARBINERIFLE', ammo = 500 },
                { weapon = 'WEAPON_PUMPSHOTGUN', ammo = 100 },
                { weapon = 'WEAPON_SMOKEGRENADE', ammo = 5 },
                { weapon = 'WEAPON_PISTOL', ammo = 150 }
            }
        },
        ['hunter'] = {
            label = ' Kit Cazador',
            description = 'Para caza y supervivencia',
            weapons = {
                { weapon = 'WEAPON_SNIPERRIFLE', ammo = 50 },
                { weapon = 'WEAPON_KNIFE', ammo = 0 },
                { weapon = 'WEAPON_MUSKET', ammo = 30 }
            }
        }
    }
}

-- 
-- v4.5 - FUEL SCRIPT INTEGRATION
-- 

Config.FuelScript = {
    enabled = true,
    -- Supported: 'LegacyFuel', 'ox_fuel', 'cdn-fuel', 'ps-fuel', 'none'
    resource = 'LegacyFuel',
    -- How to set fuel (varies by script)
    setFuelMethod = 'export', -- 'export' or 'native'
    -- Export name (if using export method)
    exportName = 'SetFuel',
    -- Native method uses DecorSetFloat for most scripts
}

-- 
-- v4.5 - REPORT PRIORITIES
-- 

Config.ReportPriority = {
    enabled = true,
    levels = {
        { id = 'low', label = 'Baja', color = '#3b82f6', icon = 'circle' },
        { id = 'medium', label = 'Media', color = '#f59e0b', icon = 'circle-half-stroke' },
        { id = 'high', label = 'Alta', color = '#ef4444', icon = 'circle-exclamation' },
        { id = 'critical', label = 'Crtica', color = '#dc2626', icon = 'triangle-exclamation' }
    },
    defaultPriority = 'medium',
    -- Auto-escalate if not handled in X minutes
    autoEscalate = {
        enabled = true,
        minutes = 10,
        escalateTo = 'high'
    }
}

-- 
-- v4.5 - VEHICLE ADVANCED OPTIONS
-- 

Config.VehicleAdvanced = {
    -- Warp player in/out of vehicle
    warpEnabled = true,
    -- Bring vehicle to admin
    bringVehicleEnabled = true,
    -- Toggle doors remotely
    toggleDoorsEnabled = true,
    -- Toggle engine remotely
    toggleEngineEnabled = true,
    -- Set fuel level
    setFuelEnabled = true,
    -- Nearby vehicle delete radius
    deleteNearbyRadius = 50.0, -- meters
}

-- 
-- v4.5 - TELEPORT FAVORITES
-- 

Config.TeleportFavorites = {
    enabled = true,
    maxPerAdmin = 20, -- Maximum saved locations per admin
    -- Default locations available to all admins
    defaults = {
        { name = 'Hospital Central', x = 298.0, y = -584.0, z = 43.3 },
        { name = 'Comisara LSPD', x = 425.0, y = -980.0, z = 30.7 },
        { name = 'Aeropuerto', x = -1037.0, y = -2738.0, z = 20.2 },
        { name = 'Casino', x = 924.0, y = 47.0, z = 81.1 },
        { name = 'Prision Bolingbroke', x = 1855.0, y = 2604.0, z = 45.7 }
    }
}

-- 
-- v4.5 - BAN EXPORT/IMPORT
-- 

Config.BanExportImport = {
    enabled = true,
    -- Format: 'json' or 'csv'
    format = 'json',
    -- Include expired bans in export
    includeExpired = false,
    -- Max import size (number of bans)
    maxImportSize = 500
}

-- 
-- v4.5 - ADMIN RANKINGS
-- 

Config.AdminRankings = {
    enabled = true,
    -- Track these actions for ranking
    trackActions = {
        'kick', 'ban', 'warn', 'report_handled', 
        'teleport', 'spawn_vehicle', 'give_item'
    },
    -- Show top X admins in diashboard
    topAdminsCount = 10,
    -- Time period for rankings ('day', 'week', 'month', 'all')
    defaultPeriod = 'week'
}

-- 
-- v4.5 - SELF ADMIN HUD
-- 

Config.SelfAdminHud = {
    enabled = true,
    -- Show speedometer when in vehicle
    showSpeedometer = true,
    -- Show FPS counter
    showFPS = true,
    -- Show entity count nearby
    showEntityCount = true,
    -- Show coords while noclipping
    showCoordsInNoclip = true,
    -- Position on screen
    position = 'bottom-right' -- 'top-left', 'top-right', 'bottom-left', 'bottom-right'
}

function GetLocale(key, ...)
    local l = Config.Locales[Config.Locale] or Config.Locales['es']
    local text = l[key] or key
    if ... then return string.format(text, ...) end
    return text
end

-- ---------------------------------------------------------------------------
-- PROFILE OVERRIDES (applied after full config load)
-- ---------------------------------------------------------------------------

local function _DeepMerge(dst, src)
    if type(dst) ~= 'table' or type(src) ~= 'table' then return dst end
    for k, v in pairs(src) do
        if type(v) == 'table' then
            if type(dst[k]) ~= 'table' then dst[k] = {} end
            _DeepMerge(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

do
    local profileName = tostring(Config.RuntimeProfile or 'default')
    if profileName ~= '' and profileName ~= 'default' then
        local preset = Config.ProfilePresets and Config.ProfilePresets[profileName] or nil
        if type(preset) == 'table' then
            _DeepMerge(Config, preset)
            print(('[LyxPanel] Runtime profile applied: %s'):format(profileName))
        else
            print(('[LyxPanel] Runtime profile not found: %s (using default)'):format(profileName))
        end
    end
end



