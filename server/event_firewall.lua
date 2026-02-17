--[[
    LyxPanel - Admin Event Firewall

    Goals:
    - Stop spoofed `lyxpanel:action:*` events before action handlers run.
    - Enforce 3 layers: allowlist, rate-limit, strict payload validation.
    - If sender has no panel access: treat as cheat trigger and permaban.
]]

local FirewallState = {
    windows = {},
    punishCooldown = {}
}

local DefaultAllowlist = {
    ['lyxpanel:action:addNote'] = true,
    ['lyxpanel:action:addVehicleFavorite'] = true,
    ['lyxpanel:action:addWhitelist'] = true,
    ['lyxpanel:action:adminChat'] = true,
    ['lyxpanel:action:adminJail'] = true,
    ['lyxpanel:action:announce'] = true,
    ['lyxpanel:action:announcement'] = true,
    ['lyxpanel:action:applyVehicleBuild'] = true,
    ['lyxpanel:action:assignReport'] = true,
    ['lyxpanel:action:ban'] = true,
    ['lyxpanel:action:banIPRange'] = true,
    ['lyxpanel:action:banOffline'] = true,
    ['lyxpanel:action:boostVehicle'] = true,
    ['lyxpanel:action:bring'] = true,
    ['lyxpanel:action:bringVehicle'] = true,
    ['lyxpanel:action:changeModel'] = true,
    ['lyxpanel:action:cleanVehicle'] = true,
    ['lyxpanel:action:clearAllDetections'] = true,
    ['lyxpanel:action:clearArea'] = true,
    ['lyxpanel:action:clearInventory'] = true,
    ['lyxpanel:action:clearLogs'] = true,
    ['lyxpanel:action:clearPed'] = true,
    ['lyxpanel:action:clearWarnings'] = true,
    ['lyxpanel:action:closeReport'] = true,
    ['lyxpanel:action:copyPosition'] = true,
    ['lyxpanel:action:deleteSelfPreset'] = true,
    ['lyxpanel:action:deleteVehicleBuild'] = true,
    ['lyxpanel:action:deleteGarageVehicle'] = true,
    ['lyxpanel:action:deleteNearbyVehicles'] = true,
    ['lyxpanel:action:deleteOutfit'] = true,
    ['lyxpanel:action:deleteTeleportFavorite'] = true,
    ['lyxpanel:action:deleteVehicle'] = true,
    ['lyxpanel:action:editBan'] = true,
    ['lyxpanel:action:flipVehicle'] = true,
    ['lyxpanel:action:freeze'] = true,
    ['lyxpanel:action:getVehicleInfo'] = true,
    ['lyxpanel:action:ghostVehicle'] = true,
    ['lyxpanel:action:giveAmmo'] = true,
    ['lyxpanel:action:giveItem'] = true,
    ['lyxpanel:action:giveLicense'] = true,
    ['lyxpanel:action:giveMoney'] = true,
    ['lyxpanel:action:giveMoneyAll'] = true,
    ['lyxpanel:action:giveVehicle'] = true,
    ['lyxpanel:action:giveWeapon'] = true,
    ['lyxpanel:action:giveWeaponKit'] = true,
    ['lyxpanel:action:godmode'] = true,
    ['lyxpanel:action:heal'] = true,
    ['lyxpanel:action:importBans'] = true,
    ['lyxpanel:action:invisible'] = true,
    ['lyxpanel:action:jail'] = true,
    ['lyxpanel:action:kick'] = true,
    ['lyxpanel:action:kill'] = true,
    ['lyxpanel:action:loadSelfPreset'] = true,
    ['lyxpanel:action:loadOutfit'] = true,
    ['lyxpanel:action:muteChat'] = true,
    ['lyxpanel:action:muteVoice'] = true,
    ['lyxpanel:action:nitro'] = true,
    ['lyxpanel:action:noclip'] = true,
    ['lyxpanel:action:privateMessage'] = true,
    ['lyxpanel:action:ragdoll'] = true,
    ['lyxpanel:action:reduceBan'] = true,
    ['lyxpanel:action:reloadConfig'] = true,
    ['lyxpanel:action:removeAllWeapons'] = true,
    ['lyxpanel:action:removeItem'] = true,
    ['lyxpanel:action:removeLicense'] = true,
    ['lyxpanel:action:removeMoney'] = true,
    ['lyxpanel:action:removeWeapon'] = true,
    ['lyxpanel:action:removeVehicleFavorite'] = true,
    ['lyxpanel:action:removeWhitelist'] = true,
    ['lyxpanel:action:repairVehicle'] = true,
    ['lyxpanel:action:revive'] = true,
    ['lyxpanel:action:reviveAll'] = true,
    ['lyxpanel:action:reviveRadius'] = true,
    ['lyxpanel:action:saveOutfit'] = true,
    ['lyxpanel:action:saveSelfPreset'] = true,
    ['lyxpanel:action:saveTeleportFavorite'] = true,
    ['lyxpanel:action:saveVehicleBuild'] = true,
    ['lyxpanel:action:scheduleAnnounce'] = true,
    ['lyxpanel:action:screenshot'] = true,
    ['lyxpanel:action:screenshotBatch'] = true,
    ['lyxpanel:action:sendReportMessage'] = true,
    ['lyxpanel:action:sendReportTemplate'] = true,
    ['lyxpanel:action:setArmor'] = true,
    ['lyxpanel:action:setHealth'] = true,
    ['lyxpanel:action:setJob'] = true,
    ['lyxpanel:action:setMoney'] = true,
    ['lyxpanel:action:setReportPriority'] = true,
    ['lyxpanel:action:setTime'] = true,
    ['lyxpanel:action:setVehicleColor'] = true,
    ['lyxpanel:action:setVehicleFuel'] = true,
    ['lyxpanel:action:freezeVehicle'] = true,
    ['lyxpanel:action:setVehicleLivery'] = true,
    ['lyxpanel:action:setVehicleExtra'] = true,
    ['lyxpanel:action:setVehicleNeon'] = true,
    ['lyxpanel:action:setVehicleWheelSmoke'] = true,
    ['lyxpanel:action:setVehiclePaintAdvanced'] = true,
    ['lyxpanel:action:setVehiclePlate'] = true,
    ['lyxpanel:action:setVehicleXenon'] = true,
    ['lyxpanel:action:setVehicleModkit'] = true,
    ['lyxpanel:action:setWeather'] = true,
    ['lyxpanel:action:slap'] = true,
    ['lyxpanel:action:spawnVehicle'] = true,
    ['lyxpanel:action:quickSpawnWarpTune'] = true,
    ['lyxpanel:action:spectate'] = true,
    ['lyxpanel:action:speedboost'] = true,
    ['lyxpanel:action:teleportCoords'] = true,
    ['lyxpanel:action:teleportBack'] = true,
    ['lyxpanel:action:teleportMarker'] = true,
    ['lyxpanel:action:teleportPlayerToPlayer'] = true,
    ['lyxpanel:action:teleportTo'] = true,
    ['lyxpanel:action:teleportToFavorite'] = true,
    ['lyxpanel:action:toggleVehicleDoors'] = true,
    ['lyxpanel:action:toggleVehicleEngine'] = true,
    ['lyxpanel:action:tpToReporter'] = true,
    ['lyxpanel:action:transferMoney'] = true,
    ['lyxpanel:action:troll:blackScreen'] = true,
    ['lyxpanel:action:troll:chicken'] = true,
    ['lyxpanel:action:troll:clones'] = true,
    ['lyxpanel:action:troll:dance'] = true,
    ['lyxpanel:action:troll:drugScreen'] = true,
    ['lyxpanel:action:troll:drunk'] = true,
    ['lyxpanel:action:troll:explode'] = true,
    ['lyxpanel:action:troll:fire'] = true,
    ['lyxpanel:action:troll:giant'] = true,
    ['lyxpanel:action:troll:invertControls'] = true,
    ['lyxpanel:action:troll:invisible'] = true,
    ['lyxpanel:action:troll:launch'] = true,
    ['lyxpanel:action:troll:ragdoll'] = true,
    ['lyxpanel:action:troll:randomPed'] = true,
    ['lyxpanel:action:troll:randomTeleport'] = true,
    ['lyxpanel:action:troll:scream'] = true,
    ['lyxpanel:action:troll:shrink'] = true,
    ['lyxpanel:action:troll:spin'] = true,
    ['lyxpanel:action:troll:stripClothes'] = true,
    ['lyxpanel:action:tuneVehicle'] = true,
    ['lyxpanel:action:unban'] = true,
    ['lyxpanel:action:unjail'] = true,
    ['lyxpanel:action:unmute'] = true,
    ['lyxpanel:action:vehicleGodmode'] = true,
    ['lyxpanel:action:warn'] = true,
    ['lyxpanel:action:warnWithEscalation'] = true,
    ['lyxpanel:action:warpIntoVehicle'] = true,
    ['lyxpanel:action:warpOutOfVehicle'] = true,
    ['lyxpanel:action:wipePlayer'] = true,
    ['lyxpanel:action:ticketAssign'] = true,
    ['lyxpanel:action:ticketReply'] = true,
    ['lyxpanel:action:ticketClose'] = true,
    ['lyxpanel:action:ticketReopen'] = true,
}

-- Extra privileged events outside lyxpanel:action:* that should be protected
-- against spoofing from non-admin users.
local DefaultProtectedEvents = {
    ['lyxpanel:panelSession'] = {
        requirePanelAccess = true,
        requireActiveSession = false,
        punishNoAccess = true,
    },
    ['lyxpanel:setStaffStatus'] = {
        requirePanelAccess = true,
        requireActiveSession = true,
        punishNoAccess = true,
    },
    ['lyxpanel:requestStaffSync'] = {
        requirePanelAccess = true,
        requireActiveSession = false,
        punishNoAccess = true,
    },
    ['lyxpanel:staffcmd:requestRevive'] = {
        requirePanelAccess = true,
        requiredPermission = 'canRevive',
        requireActiveSession = false,
        punishNoAccess = true,
    },
    ['lyxpanel:staffcmd:requestInstantRespawn'] = {
        requirePanelAccess = true,
        requiredPermission = 'canRevive',
        requireActiveSession = false,
        punishNoAccess = true,
    },
    ['lyxpanel:staffcmd:requestAmmoRefill'] = {
        requirePanelAccess = true,
        requiredPermission = 'canGiveWeapons',
        requireActiveSession = false,
        punishNoAccess = true,
    },
    ['lyxpanel:reports:claim'] = {
        requirePanelAccess = true,
        requiredPermission = 'canManageReports',
        requireActiveSession = true,
        punishNoAccess = true,
    },
    ['lyxpanel:reports:resolve'] = {
        requirePanelAccess = true,
        requiredPermission = 'canManageReports',
        requireActiveSession = true,
        punishNoAccess = true,
    },
    ['lyxpanel:reports:get'] = {
        requirePanelAccess = true,
        requiredPermission = 'canManageReports',
        requireActiveSession = false,
        punishNoAccess = true,
    },
    ['lyxpanel:danger:approve'] = {
        requirePanelAccess = true,
        requireActiveSession = true,
        punishNoAccess = true,
    },
}

-- Additional strict schemas for high-risk actions.
-- These do not replace server-side validation in action handlers; they add a pre-filter.
local DefaultSchemas = {
    ['lyxpanel:action:kick'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'string', 'nil' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } },
        stringRules = { [2] = { maxLen = 200 } }
    },
    ['lyxpanel:action:ban'] = {
        minArgs = 2,
        maxArgs = 4,
        types = { [1] = 'number', [2] = 'string', [3] = { 'string', 'number', 'nil' }, [4] = { 'boolean', 'nil' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } },
        stringRules = { [2] = { minLen = 3, maxLen = 200 } }
    },
    ['lyxpanel:action:unban'] = {
        minArgs = 2,
        maxArgs = 3,
        types = { [1] = 'string', [2] = 'string', [3] = { 'boolean', 'nil' } },
        stringRules = { [1] = { minLen = 6, maxLen = 128 }, [2] = { minLen = 3, maxLen = 200 } }
    },
    ['lyxpanel:action:giveMoney'] = {
        minArgs = 3,
        maxArgs = 4,
        types = { [1] = 'number', [2] = 'string', [3] = 'number', [4] = { 'boolean', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [3] = { integer = true, min = 1, max = 10000000 }
        },
        enums = { [2] = { money = true, bank = true, black_money = true } }
    },
    ['lyxpanel:action:setMoney'] = {
        minArgs = 3,
        maxArgs = 4,
        types = { [1] = 'number', [2] = 'string', [3] = 'number', [4] = { 'boolean', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [3] = { integer = true, min = 0, max = 10000000 }
        },
        enums = { [2] = { money = true, bank = true, black_money = true } }
    },
    ['lyxpanel:action:removeMoney'] = {
        minArgs = 3,
        maxArgs = 4,
        types = { [1] = 'number', [2] = 'string', [3] = 'number', [4] = { 'boolean', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [3] = { integer = true, min = 1, max = 10000000 }
        },
        enums = { [2] = { money = true, bank = true, black_money = true } }
    },
    ['lyxpanel:action:transferMoney'] = {
        minArgs = 4,
        maxArgs = 5,
        types = {
            [1] = 'number',
            [2] = 'number',
            [3] = 'string',
            [4] = 'number',
            [5] = { 'boolean', 'nil' }
        },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 4096 },
            [4] = { integer = true, min = 1, max = 10000000 }
        },
        enums = { [3] = { money = true, bank = true, black_money = true } }
    },
    ['lyxpanel:action:giveWeapon'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'string', [3] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [3] = { integer = true, min = 1, max = 2000 }
        },
        stringRules = { [2] = { minLen = 6, maxLen = 64 } }
    },
    ['lyxpanel:action:giveAmmo'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'string', [3] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [3] = { integer = true, min = 1, max = 2000 }
        },
        stringRules = { [2] = { minLen = 6, maxLen = 64 } }
    },
    ['lyxpanel:action:giveItem'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'string', [3] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [3] = { integer = true, min = 1, max = 1000 }
        },
        stringRules = { [2] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:removeItem'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'string', [3] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [3] = { integer = true, min = 1, max = 1000 }
        },
        stringRules = { [2] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:spawnVehicle'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } },
        stringRules = { [2] = { minLen = 1, maxLen = 32 } }
    },
    ['lyxpanel:action:quickSpawnWarpTune'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } },
        stringRules = { [2] = { minLen = 1, maxLen = 32 } }
    },
    ['lyxpanel:action:setJob'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'string', [3] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [3] = { integer = true, min = 0, max = 20 }
        },
        stringRules = { [2] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:setArmor'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [2] = { integer = true, min = 0, max = 100 }
        }
    },
    ['lyxpanel:action:setHealth'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [2] = { integer = true, min = 1, max = 200 }
        }
    },
    ['lyxpanel:action:teleportCoords'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'number', [3] = 'number' },
        numberRanges = {
            [1] = { min = -10000.0, max = 10000.0 },
            [2] = { min = -10000.0, max = 10000.0 },
            [3] = { min = -2000.0, max = 4000.0 }
        }
    },
    ['lyxpanel:action:clearAllDetections'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'string', [2] = { 'boolean', 'nil' } },
        stringRules = { [1] = { minLen = 3, maxLen = 200 } }
    },
    ['lyxpanel:action:clearLogs'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'string', [2] = { 'boolean', 'nil' } },
        stringRules = { [1] = { minLen = 3, maxLen = 200 } }
    },
    ['lyxpanel:action:wipePlayer'] = {
        minArgs = 3,
        maxArgs = 4,
        types = { [1] = 'number', [2] = 'string', [3] = 'string', [4] = { 'boolean', 'nil' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } },
        stringRules = { [2] = { minLen = 3, maxLen = 24 }, [3] = { minLen = 3, maxLen = 200 } }
    },
    ['lyxpanel:action:ticketAssign'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 1000000000 } }
    },
    ['lyxpanel:action:ticketReply'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = { [1] = { integer = true, min = 1, max = 1000000000 } },
        stringRules = { [2] = { minLen = 1, maxLen = 900, trim = true } }
    },
    ['lyxpanel:action:ticketClose'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'string', 'nil' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 1000000000 } },
        stringRules = { [2] = { maxLen = 200, trim = true } }
    },
    ['lyxpanel:action:ticketReopen'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 1000000000 } }
    },
    ['lyxpanel:action:banOffline'] = {
        minArgs = 2,
        maxArgs = 4,
        types = { [1] = 'string', [2] = 'string', [3] = { 'number', 'string', 'nil' }, [4] = { 'string', 'nil' } },
        stringRules = {
            [1] = { minLen = 6, maxLen = 128 },
            [2] = { minLen = 3, maxLen = 200 },
            [4] = { minLen = 1, maxLen = 100 }
        },
        numberRanges = {
            [3] = { integer = true, min = 0, max = 8760 }
        }
    },
    ['lyxpanel:action:banIPRange'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'string', [2] = 'string' },
        stringRules = { [1] = { minLen = 7, maxLen = 32 }, [2] = { minLen = 3, maxLen = 200 } }
    },
    ['lyxpanel:action:reduceBan'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 2147483647 },
            [2] = { integer = true, min = 1, max = 8760 }
        }
    },
    ['lyxpanel:action:jail'] = {
        minArgs = 2,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'number', [3] = { 'string', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 240 }
        },
        stringRules = { [3] = { minLen = 0, maxLen = 200 } }
    },
    ['lyxpanel:action:muteChat'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 240 }
        }
    },
    ['lyxpanel:action:muteVoice'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 240 }
        }
    },
    ['lyxpanel:action:unjail'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 }
        }
    },
    ['lyxpanel:action:unmute'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 }
        }
    },
    ['lyxpanel:action:clearWarnings'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 }
        }
    },
    ['lyxpanel:action:adminJail'] = {
        minArgs = 2,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'number', [3] = { 'boolean', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 240 }
        }
    },
    ['lyxpanel:action:tpToReporter'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 }
        }
    },
    ['lyxpanel:action:setVehiclePlate'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 }
        },
        stringRules = { [2] = { minLen = 1, maxLen = 16 } }
    },
    ['lyxpanel:action:setVehicleColor'] = {
        minArgs = 3,
        maxArgs = 3,
        types = {
            [1] = 'number',
            [2] = { 'number', 'table' },
            [3] = { 'number', 'table' }
        },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 }
        }
    },
    ['lyxpanel:action:giveLicense'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 }
        },
        stringRules = { [2] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:removeLicense'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 }
        },
        stringRules = { [2] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:giveVehicle'] = {
        minArgs = 2,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'string', [3] = { 'string', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 }
        },
        stringRules = {
            [2] = { minLen = 1, maxLen = 32 },
            [3] = { minLen = 0, maxLen = 16 }
        }
    },
    ['lyxpanel:action:deleteGarageVehicle'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 }
        },
        stringRules = { [2] = { minLen = 1, maxLen = 16 } }
    },
    ['lyxpanel:action:setVehicleFuel'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [2] = { min = 0.0, max = 100.0 }
        }
    },
    ['lyxpanel:action:freezeVehicle'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'boolean', 'number', 'string' } },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 }
        }
    },
    ['lyxpanel:action:setVehicleLivery'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [2] = { integer = true, min = -1, max = 200 }
        }
    },
    ['lyxpanel:action:setVehicleExtra'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'number', [3] = { 'boolean', 'number', 'string' } },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [2] = { integer = true, min = 0, max = 20 }
        }
    },
    ['lyxpanel:action:setVehicleNeon'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = { 'boolean', 'number', 'string' }, [3] = 'table' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 }
        }
    },
    ['lyxpanel:action:setVehicleWheelSmoke'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'table' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 }
        }
    },
    ['lyxpanel:action:setVehiclePaintAdvanced'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'number', [3] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [2] = { integer = true, min = 0, max = 160 },
            [3] = { integer = true, min = 0, max = 160 }
        }
    },
    ['lyxpanel:action:setVehicleXenon'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = { 'boolean', 'number', 'string' }, [3] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [3] = { integer = true, min = -1, max = 13 }
        }
    },
    ['lyxpanel:action:setVehicleModkit'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'table' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 }
        },
        tableRules = {
            [2] = {
                maxKeys = 6,
                allowExtraKeys = false,
                fields = {
                    engine = { required = true, type = 'number', integer = true, min = -1, max = 5 },
                    brakes = { required = true, type = 'number', integer = true, min = -1, max = 5 },
                    transmission = { required = true, type = 'number', integer = true, min = -1, max = 5 },
                    suspension = { required = true, type = 'number', integer = true, min = -1, max = 5 },
                    armor = { required = true, type = 'number', integer = true, min = -1, max = 5 },
                    turbo = { required = true, boolLike = true }
                }
            }
        }
    },
    ['lyxpanel:action:warpIntoVehicle'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [2] = { integer = true, min = 1, max = 4096 }
        }
    },
    ['lyxpanel:action:warpOutOfVehicle'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 }
        }
    },
    ['lyxpanel:action:sendReportMessage'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = { 'number', 'nil' }, [3] = 'string' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 2147483647 },
            [2] = { integer = true, min = 1, max = 4096 }
        },
        stringRules = { [3] = { minLen = 1, maxLen = 500 } }
    },
    ['lyxpanel:action:sendReportTemplate'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = { 'number', 'nil' }, [3] = 'string' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 2147483647 },
            [2] = { integer = true, min = 1, max = 4096 }
        },
        stringRules = { [3] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:setReportPriority'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 2147483647 }
        },
        enums = { [2] = { low = true, medium = true, high = true, critical = true, urgent = true } }
    },
    ['lyxpanel:action:giveMoneyAll'] = {
        minArgs = 1,
        maxArgs = 3,
        types = { [1] = 'number', [2] = { 'string', 'nil' }, [3] = { 'boolean', 'nil' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 10000000 } },
        enums = { [2] = { money = true, bank = true, black_money = true } }
    },
    ['lyxpanel:action:clearArea'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'boolean', 'nil' } },
        numberRanges = { [1] = { min = 1, max = 1000 } }
    },
    ['lyxpanel:action:announcement'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'string', [2] = { 'boolean', 'nil' } },
        stringRules = { [1] = { minLen = 3, maxLen = 250 } }
    },
    ['lyxpanel:action:addNote'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } },
        stringRules = { [2] = { minLen = 1, maxLen = 400 } }
    },
    ['lyxpanel:action:adminChat'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'string' },
        stringRules = { [1] = { minLen = 1, maxLen = 500 } }
    },
    ['lyxpanel:action:announce'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'string', [2] = { 'string', 'nil' } },
        stringRules = { [1] = { minLen = 1, maxLen = 250 }, [2] = { minLen = 0, maxLen = 32 } }
    },
    ['lyxpanel:action:assignReport'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } }
    },
    ['lyxpanel:action:bring'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:closeReport'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'string', 'nil' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } },
        stringRules = { [2] = { minLen = 0, maxLen = 400 } }
    },
    ['lyxpanel:action:changeModel'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } },
        stringRules = { [2] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:boostVehicle'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:bringVehicle'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:cleanVehicle'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:clearPed'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'boolean', 'nil' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:clearInventory'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'boolean', 'nil' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:copyPosition'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:deleteNearbyVehicles'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:action:deleteVehicle'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:flipVehicle'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:freeze'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'boolean', 'number', 'string' } },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:getVehicleInfo'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:action:ghostVehicle'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'boolean', 'number', 'string' } },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:heal'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:godmode'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:action:importBans'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'table', [2] = { 'boolean', 'nil' } }
    },
    ['lyxpanel:action:invisible'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:action:kill'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:privateMessage'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } },
        stringRules = { [2] = { minLen = 1, maxLen = 500 } }
    },
    ['lyxpanel:action:ragdoll'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 100, max = 60000 }
        }
    },
    ['lyxpanel:action:removeAllWeapons'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:removeWeapon'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } },
        stringRules = { [2] = { minLen = 6, maxLen = 64 } }
    },
    ['lyxpanel:action:repairVehicle'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:revive'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:reviveAll'] = {
        minArgs = 0,
        maxArgs = 1,
        types = { [1] = { 'boolean', 'nil' } }
    },
    ['lyxpanel:action:reviveRadius'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'boolean', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 5, max = 500 }
        }
    },
    ['lyxpanel:action:scheduleAnnounce'] = {
        minArgs = 2,
        maxArgs = 3,
        types = { [1] = 'string', [2] = 'number', [3] = { 'number', 'nil' } },
        stringRules = { [1] = { minLen = 1, maxLen = 250 } },
        numberRanges = {
            [2] = { integer = true, min = 1, max = 1440 },
            [3] = { integer = true, min = 1, max = 1440 }
        }
    },
    ['lyxpanel:action:screenshot'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:screenshotBatch'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'table' },
        tableRules = {
            [1] = {
                maxKeys = 32
            }
        }
    },
    ['lyxpanel:action:setTime'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 0, max = 23 },
            [2] = { integer = true, min = 0, max = 59 }
        }
    },
    ['lyxpanel:action:setWeather'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'string' },
        stringRules = { [1] = { minLen = 1, maxLen = 32 } }
    },
    ['lyxpanel:action:slap'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:spectate'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:nitro'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:action:noclip'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:action:saveOutfit'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'string', [2] = 'table' },
        stringRules = { [1] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:speedboost'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:action:teleportMarker'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:action:teleportBack'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:action:teleportTo'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:toggleVehicleDoors'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = -1, max = 4096 },
            [2] = { integer = true, min = -1, max = 7 }
        }
    },
    ['lyxpanel:action:toggleVehicleEngine'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:tuneVehicle'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } }
    },
    ['lyxpanel:action:vehicleGodmode'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:action:warn'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } },
        stringRules = { [2] = { minLen = 3, maxLen = 200 } }
    },
    ['lyxpanel:action:warnWithEscalation'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'string' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } },
        stringRules = { [2] = { minLen = 3, maxLen = 200 } }
    },
    ['lyxpanel:action:troll:explode'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:troll:fire'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:troll:launch'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { min = 1, max = 200.0 }
        }
    },
    ['lyxpanel:action:troll:ragdoll'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:troll:drunk'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 180 }
        }
    },
    ['lyxpanel:action:troll:drugScreen'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 180 }
        }
    },
    ['lyxpanel:action:troll:blackScreen'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 180 }
        }
    },
    ['lyxpanel:action:troll:scream'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:troll:randomTeleport'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:troll:stripClothes'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:troll:invertControls'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 180 }
        }
    },
    ['lyxpanel:action:troll:randomPed'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:troll:chicken'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:troll:dance'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } }
    },
    ['lyxpanel:action:troll:invisible'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 180 }
        }
    },
    ['lyxpanel:action:troll:spin'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 180 }
        }
    },
    ['lyxpanel:action:troll:shrink'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 180 }
        }
    },
    ['lyxpanel:action:troll:giant'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 180 }
        }
    },
    ['lyxpanel:action:troll:clones'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'number', [2] = { 'number', 'nil' } },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 20 }
        }
    },
    -- Presets / Pro tools (self presets + vehicle builds/favorites/history)
    ['lyxpanel:action:saveSelfPreset'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'string', [2] = 'table' },
        stringRules = { [1] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:deleteSelfPreset'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } }
    },
    ['lyxpanel:action:loadSelfPreset'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } }
    },
    ['lyxpanel:action:saveVehicleBuild'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'string', [2] = 'table' },
        stringRules = { [1] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:deleteVehicleBuild'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } }
    },
    ['lyxpanel:action:applyVehicleBuild'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } }
    },
    ['lyxpanel:action:addVehicleFavorite'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'string', [2] = { 'string', 'nil' } },
        stringRules = { [1] = { minLen = 1, maxLen = 32 }, [2] = { minLen = 0, maxLen = 100 } }
    },
    ['lyxpanel:action:removeVehicleFavorite'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } }
    },
    ['lyxpanel:action:addWhitelist'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'string', [2] = { 'string', 'nil' } },
        stringRules = {
            [1] = { minLen = 6, maxLen = 128 },
            [2] = { minLen = 0, maxLen = 100 }
        }
    },
    ['lyxpanel:action:removeWhitelist'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = { 'number', 'string' } }
    },
    ['lyxpanel:action:saveTeleportFavorite'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'string', [2] = 'table' },
        stringRules = { [1] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:deleteTeleportFavorite'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } }
    },
    ['lyxpanel:action:teleportToFavorite'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'table' }
    },
    ['lyxpanel:action:teleportPlayerToPlayer'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 1, max = 4096 },
            [2] = { integer = true, min = 1, max = 4096 }
        }
    },
    ['lyxpanel:action:giveWeaponKit'] = {
        minArgs = 2,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'string', [3] = { 'boolean', 'nil' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 4096 } },
        stringRules = { [2] = { minLen = 1, maxLen = 64 } }
    },
    ['lyxpanel:action:editBan'] = {
        minArgs = 3,
        maxArgs = 3,
        types = { [1] = 'number', [2] = 'string', [3] = { 'number', 'string' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } },
        stringRules = { [2] = { minLen = 3, maxLen = 200 } }
    },
    ['lyxpanel:action:loadOutfit'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } }
    },
    ['lyxpanel:action:deleteOutfit'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'number' },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } }
    },
    ['lyxpanel:action:reloadConfig'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:setStaffStatus'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = 'boolean', [2] = { 'string', 'nil' } },
        stringRules = { [2] = { minLen = 0, maxLen = 64 } }
    },
    ['lyxpanel:requestStaffSync'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:panelSession'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = 'boolean' }
    },
    ['lyxpanel:reports:claim'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = { 'number', 'string' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } },
        stringRules = { [1] = { minLen = 1, maxLen = 16 } }
    },
    ['lyxpanel:reports:resolve'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = { 'number', 'string' }, [2] = { 'string', 'nil' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } },
        stringRules = { [1] = { minLen = 1, maxLen = 16 }, [2] = { minLen = 0, maxLen = 400 } }
    },
    ['lyxpanel:reports:get'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:danger:approve'] = {
        minArgs = 1,
        maxArgs = 1,
        types = { [1] = { 'number', 'string' } },
        numberRanges = { [1] = { integer = true, min = 1, max = 2147483647 } },
        stringRules = { [1] = { minLen = 1, maxLen = 16 } }
    },
    ['lyxpanel:reports:create'] = {
        minArgs = 1,
        maxArgs = 2,
        types = { [1] = { 'number', 'nil' }, [2] = { 'string', 'nil' } },
        numberRanges = { [1] = { integer = true, min = -1, max = 4096 } },
        stringRules = { [2] = { minLen = 1, maxLen = 500 } }
    },
    ['lyxpanel:staffcmd:checkAdminStatus'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:staffcmd:requestRevive'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:staffcmd:requestInstantRespawn'] = {
        minArgs = 0,
        maxArgs = 0
    },
    ['lyxpanel:staffcmd:requestAmmoRefill'] = {
        minArgs = 2,
        maxArgs = 2,
        types = { [1] = 'number', [2] = 'number' },
        numberRanges = {
            [1] = { integer = true, min = 0, max = 4294967295 },
            [2] = { integer = true, min = 1, max = 9999 }
        }
    },
    ['lyxpanel:spectate:end'] = {
        minArgs = 0,
        maxArgs = 0
    }
}

local function _SplitArgs(argList)
    if type(argList) ~= 'string' then
        return {}
    end

    local out = {}
    for raw in argList:gmatch('[^,]+') do
        local name = (raw:match('^%s*(.-)%s*$') or ''):lower()
        if name ~= '' then
            out[#out + 1] = name
        end
    end
    return out
end

local function _ContainsAny(value, words)
    if type(value) ~= 'string' or type(words) ~= 'table' then
        return false
    end
    for _, w in ipairs(words) do
        if value:find(w, 1, true) then
            return true
        end
    end
    return false
end

local function _InferArgRules(argName)
    local n = tostring(argName or ''):lower()
    if n == '' then
        return nil, nil, nil, nil
    end

    if n == 'dryrun' or n == 'opened' or n == 'active' or n == 'freeze' or n == 'enabled' then
        return 'boolean', nil, nil, nil
    end

    if _ContainsAny(n, { 'data', 'coords', 'location', 'bans', 'outfit', 'payload' }) then
        return 'table', nil, nil, nil
    end

    if n == 'x' or n == 'y' or n == 'z' then
        return 'number', { min = -100000.0, max = 100000.0 }, nil, nil
    end

    if _ContainsAny(n, { 'id', 'target', 'player', 'report', 'banid', 'outfitid', 'favoriteid' }) then
        local minValue = 1
        if _ContainsAny(n, { 'target', 'player' }) then
            minValue = -1
        end
        return 'number', { integer = true, min = minValue, max = 2147483647 }, nil, nil
    end

    if _ContainsAny(n, { 'amount', 'count', 'ammo', 'hours', 'minute', 'time', 'duration', 'delay' }) then
        return 'number', { integer = true, min = 0, max = 10000000 }, nil, nil
    end

    if _ContainsAny(n, { 'radius' }) then
        return 'number', { min = 0.1, max = 5000.0 }, nil, nil
    end

    if _ContainsAny(n, { 'grade' }) then
        return 'number', { integer = true, min = 0, max = 100 }, nil, nil
    end

    if _ContainsAny(n, { 'fuel' }) then
        return 'number', { min = 0, max = 100 }, nil, nil
    end

    if _ContainsAny(n, { 'force' }) then
        return 'number', { min = 0.1, max = 250.0 }, nil, nil
    end

    if _ContainsAny(n, { 'door' }) then
        return 'number', { integer = true, min = -1, max = 10 }, nil, nil
    end

    if _ContainsAny(n, { 'hash' }) then
        return 'number', { integer = true, min = 0, max = 4294967295 }, nil, nil
    end

    if n == 'account' or n == 'accounttype' then
        return 'string', nil, { minLen = 3, maxLen = 32 }, { money = true, bank = true, black_money = true }
    end

    if _ContainsAny(n, { 'reason' }) then
        return 'string', nil, { minLen = 1, maxLen = 250 }, nil
    end

    if _ContainsAny(n, { 'message', 'note' }) then
        return 'string', nil, { minLen = 1, maxLen = 500 }, nil
    end

    if _ContainsAny(n, { 'identifier' }) then
        return 'string', nil, { minLen = 6, maxLen = 128 }, nil
    end

    if _ContainsAny(n, { 'name', 'playername', 'outfitname' }) then
        return 'string', nil, { minLen = 1, maxLen = 100 }, nil
    end

    if _ContainsAny(n, { 'model', 'vehicle', 'weapon', 'item', 'job', 'weather', 'license' }) then
        return 'string', nil, { minLen = 1, maxLen = 64 }, nil
    end

    if _ContainsAny(n, { 'confirm', 'plate', 'priority', 'type' }) then
        return 'string', nil, { minLen = 1, maxLen = 32 }, nil
    end

    if _ContainsAny(n, { 'iprange' }) then
        return 'string', nil, { minLen = 7, maxLen = 64 }, nil
    end

    return { 'string', 'number', 'boolean', 'nil' }, nil, nil, nil
end

local function _BuildSchemaFromArgs(args)
    local schema = {
        minArgs = #args,
        maxArgs = #args,
        types = {},
        numberRanges = {},
        stringRules = {},
        enums = {},
    }

    for i, argName in ipairs(args) do
        local expected, numRule, strRule, enumRule = _InferArgRules(argName)
        if expected ~= nil then
            schema.types[i] = expected
        end
        if type(numRule) == 'table' then
            schema.numberRanges[i] = numRule
        end
        if type(strRule) == 'table' then
            schema.stringRules[i] = strRule
        end
        if type(enumRule) == 'table' then
            schema.enums[i] = enumRule
        end
    end

    if next(schema.types) == nil then schema.types = nil end
    if next(schema.numberRanges) == nil then schema.numberRanges = nil end
    if next(schema.stringRules) == nil then schema.stringRules = nil end
    if next(schema.enums) == nil then schema.enums = nil end
    return schema
end

local _EventSignatureCache = nil

local function _CollectEventSignatures()
    if _EventSignatureCache ~= nil then
        return _EventSignatureCache
    end

    local out = {}
    local files = {
        'server/actions.lua',
        'server/actions_extended.lua',
        'server/features_v45.lua',
        'server/main.lua',
        'server/reports.lua',
        'server/staff_commands.lua',
    }

    for _, filePath in ipairs(files) do
        local raw = LoadResourceFile(GetCurrentResourceName(), filePath)
        if type(raw) == 'string' and raw ~= '' then
            -- Inline form: RegisterNetEvent('event', function(a, b) ... end)
            for eventName, args in raw:gmatch("RegisterNetEvent%('([^']+)'%s*,%s*function%(([^)]*)%)") do
                if type(eventName) == 'string' and eventName:sub(1, 9) == 'lyxpanel:' then
                    out[eventName] = _SplitArgs(args)
                end
            end

            -- Two-line form:
            -- RegisterNetEvent('event')
            -- AddEventHandler('event', function(a, b) ... end)
            for eventName, args in raw:gmatch("AddEventHandler%('([^']+)'%s*,%s*function%(([^)]*)%)") do
                if type(eventName) == 'string' and eventName:sub(1, 9) == 'lyxpanel:' then
                    out[eventName] = _SplitArgs(args)
                end
            end

            -- Register-only fallback (no args known yet).
            for eventName in raw:gmatch("RegisterNetEvent%('([^']+)'%)") do
                if type(eventName) == 'string' and eventName:sub(1, 9) == 'lyxpanel:' and out[eventName] == nil then
                    out[eventName] = {}
                end
            end
        end
    end

    _EventSignatureCache = out
    return out
end

local function _BuildSchemaMap(customSchemas)
    local out = {}

    for eventName, schema in pairs(DefaultSchemas) do
        out[eventName] = schema
    end

    local signatures = _CollectEventSignatures()
    for eventName, args in pairs(signatures) do
        if out[eventName] == nil then
            out[eventName] = _BuildSchemaFromArgs(args)
        end
    end

    for eventName, _ in pairs(DefaultAllowlist) do
        if out[eventName] == nil then
            out[eventName] = { minArgs = 0, maxArgs = 8 }
        end
    end

    for eventName, _ in pairs(DefaultProtectedEvents) do
        if out[eventName] == nil then
            out[eventName] = { minArgs = 0, maxArgs = 4 }
        end
    end

    if type(customSchemas) == 'table' then
        for eventName, schema in pairs(customSchemas) do
            if schema == false then
                out[eventName] = nil
            elseif type(schema) == 'table' then
                out[eventName] = schema
            end
        end
    end

    return out
end

local function _BuildProtectedEventMap(customProtected)
    local out = {}

    for eventName, rule in pairs(DefaultProtectedEvents) do
        out[eventName] = rule
    end

    if type(customProtected) == 'table' then
        for eventName, rule in pairs(customProtected) do
            if rule == false then
                out[eventName] = nil
            elseif type(rule) == 'table' then
                out[eventName] = rule
            end
        end
    end

    return out
end

local _CfgCache = nil
local _CfgCacheAt = 0
local _CfgCacheTtlMs = 1000

local function _GetCfg()
    local now = GetGameTimer()
    if _CfgCache and (now - _CfgCacheAt) < _CfgCacheTtlMs then
        return _CfgCache
    end

    local cfg = Config and Config.Security and Config.Security.adminEventFirewall or {}
    local schemaOnlyPrefixes = cfg.schemaOnlyPrefixes
    if type(schemaOnlyPrefixes) ~= 'table' then
        schemaOnlyPrefixes = {
            'lyxpanel:reports:',
            'lyxpanel:staffcmd:',
            'lyxpanel:spectate:'
        }
    end

    local built = {
        enabled = cfg.enabled ~= false,
        actionPrefix = tostring(cfg.actionPrefix or 'lyxpanel:action:'),
        strictAllowlist = cfg.strictAllowlist ~= false,
        validateAllLyxpanelEvents = cfg.validateAllLyxpanelEvents ~= false,
        schemaOnlyPrefixes = schemaOnlyPrefixes,
        requireActiveSession = cfg.requireActiveSession ~= false,
        sessionTtlMs = math.max(tonumber(cfg.sessionTtlMs) or (10 * 60 * 1000), 30000),
        -- If the session state provider is unavailable, default behavior is fail-open to avoid breaking production.
        -- In hostile environments you can set this to false to fail-closed.
        sessionStateFailOpen = cfg.sessionStateFailOpen ~= false,
        maxEventsPerWindow = math.max(tonumber(cfg.maxEventsPerWindow) or 240, 10),
        windowMs = math.max(tonumber(cfg.windowMs) or 10000, 500),
        maxArgs = math.max(tonumber(cfg.maxArgs) or 12, 1),
        maxDepth = math.max(tonumber(cfg.maxDepth) or 6, 1),
        maxKeysPerTable = math.max(tonumber(cfg.maxKeysPerTable) or 96, 4),
        maxTotalKeys = math.max(tonumber(cfg.maxTotalKeys) or 512, 16),
        maxStringLen = math.max(tonumber(cfg.maxStringLen) or 512, 16),
        permabanOnNoAccess = cfg.permabanOnNoAccess ~= false,
        banDuration = tonumber(cfg.banDuration) or 0,
        banReason = tostring(cfg.banReason or 'Cheating detected (admin event spoof)'),
        banBy = tostring(cfg.banBy or 'LyxPanel Firewall'),
        punishCooldownMs = math.max(tonumber(cfg.punishCooldownMs) or 15000, 1000),
        notifyPlayer = cfg.notifyPlayer ~= false,
        schemaValidation = cfg.schemaValidation ~= false,
        schemas = _BuildSchemaMap(cfg.schemas),
        protectedEvents = _BuildProtectedEventMap(cfg.protectedEvents),
        actionSecurity = cfg.actionSecurity or {}
    }

    _CfgCache = built
    _CfgCacheAt = now
    return built
end

local function _StartsWith(value, prefix)
    return type(value) == 'string' and type(prefix) == 'string' and value:sub(1, #prefix) == prefix
end

local function _GetEventRule(eventName, cfg)
    if _StartsWith(eventName, cfg.actionPrefix) then
        return {
            isAction = true,
            schemaOnly = false,
            requirePanelAccess = true,
            requiredPermission = nil,
            requireActiveSession = cfg.requireActiveSession == true,
            punishNoAccess = true,
            notifyPlayer = cfg.notifyPlayer ~= false,
        }
    end

    local r = cfg.protectedEvents and cfg.protectedEvents[eventName]
    if type(r) == 'table' then
        return {
            isAction = false,
            schemaOnly = false,
            requirePanelAccess = r.requirePanelAccess ~= false,
            requiredPermission = type(r.requiredPermission) == 'string' and r.requiredPermission or nil,
            requireActiveSession = r.requireActiveSession == true,
            punishNoAccess = r.punishNoAccess ~= false,
            notifyPlayer = r.notifyPlayer ~= false,
        }
    end

    if cfg.validateAllLyxpanelEvents == true and _StartsWith(eventName, 'lyxpanel:') then
        local schemaOnly = false

        if type(cfg.schemaOnlyPrefixes) == 'table' and #cfg.schemaOnlyPrefixes > 0 then
            for _, prefix in ipairs(cfg.schemaOnlyPrefixes) do
                if _StartsWith(eventName, tostring(prefix or '')) then
                    schemaOnly = true
                    break
                end
            end
        end

        -- If the event has an explicit schema and isn't action/protected, validate it anyway.
        if not schemaOnly and type(cfg.schemas) == 'table' and type(cfg.schemas[eventName]) == 'table' then
            schemaOnly = true
        end

        if schemaOnly then
            return {
                isAction = false,
                schemaOnly = true,
                requirePanelAccess = false,
                requiredPermission = nil,
                requireActiveSession = false,
                punishNoAccess = false,
                notifyPlayer = false,
            }
        end
    end

    return nil
end

local function _HasRequiredPermission(src, rule)
    if not rule or type(rule.requiredPermission) ~= 'string' or rule.requiredPermission == '' then
        return true
    end

    if type(HasPermission) == 'function' then
        local ok, allowed = pcall(function()
            return HasPermission(src, rule.requiredPermission)
        end)
        if ok then
            return allowed == true
        end
    end

    -- Fallback for early-start scenarios where HasPermission is not available yet.
    return IsPlayerAceAllowed(src, 'lyxpanel.admin') or IsPlayerAceAllowed(src, 'lyxpanel.access')
end

local function _GetIdentifier(src, idType)
    idType = idType or 'license'
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if string.find(id, idType .. ':') then
            return id
        end
    end
    return 'unknown'
end

local function _CanTrustAccessCheck()
    if _G.ESX then return true end
    if LyxPanel and LyxPanel.GetESX then
        return LyxPanel.GetESX() ~= nil
    end
    return false
end

local function _IsAllowlisted(eventName)
    local custom = Config and Config.Security and Config.Security.adminEventFirewall and
        Config.Security.adminEventFirewall.allowlist or nil

    if type(custom) == 'table' then
        if custom[eventName] ~= nil then
            return custom[eventName] == true
        end
    end

    return DefaultAllowlist[eventName] == true
end

local function _HasActivePanelSession(src, cfg)
    if cfg.requireActiveSession ~= true then
        return true
    end

    local ttlMs = tonumber(cfg.sessionTtlMs) or (10 * 60 * 1000)
    if type(IsPanelSessionActive) == 'function' then
        return IsPanelSessionActive(src, ttlMs) == true
    end

    if GetResourceState('lyx-panel') == 'started' and exports['lyx-panel'] and exports['lyx-panel'].IsPanelSessionActive then
        local ok, active = pcall(function()
            return exports['lyx-panel']:IsPanelSessionActive(src, ttlMs)
        end)
        return ok == true and active == true
    end

    -- If session state is unavailable:
    -- - default is fail-open to avoid breaking production,
    -- - in hostile mode you can set sessionStateFailOpen=false to fail-closed.
    return cfg.sessionStateFailOpen ~= false
end

local function _HasSecurityEnvelopeArg(value)
    return type(value) == 'table' and type(value.__lyxsec) == 'table'
end

local function _GetEffectiveArgCount(eventData)
    if type(eventData) ~= 'table' then
        return 0, false
    end

    local argCount = #eventData
    if argCount > 0 and _HasSecurityEnvelopeArg(eventData[argCount]) then
        return argCount - 1, true
    end

    return argCount, false
end

local function _ValidateActionSecurity(src, eventName, eventData, cfg, eventRule)
    local secRoot = cfg and cfg.actionSecurity
    if type(secRoot) ~= 'table' or secRoot.enabled == false then
        return true, nil, nil
    end

    if type(ValidatePanelActionEnvelope) == 'function' then
        local ok, allowed, reason, meta = pcall(ValidatePanelActionEnvelope, src, eventName, eventData, eventRule)
        if ok then
            if allowed == true then
                return true, nil, meta
            end
            return false, tostring(reason or 'security_validation_failed'), meta
        end
        return false, 'security_validator_error', { error = tostring(allowed) }
    end

    if GetResourceState('lyx-panel') == 'started' and exports['lyx-panel'] and exports['lyx-panel'].ValidatePanelActionEnvelope then
        local ok, allowed, reason, meta = pcall(function()
            return exports['lyx-panel']:ValidatePanelActionEnvelope(src, eventName, eventData, eventRule)
        end)
        if ok then
            if allowed == true then
                return true, nil, meta
            end
            return false, tostring(reason or 'security_validation_failed'), meta
        end
        return false, 'security_validator_error', { error = tostring(allowed) }
    end

    return false, 'security_validator_unavailable', {}
end

local function _LogSecurity(src, action, eventName, reason, details)
    local playerName = GetPlayerName(src) or 'unknown'
    local identifier = _GetIdentifier(src, 'license')
    local payload = {
        event = eventName,
        reason = reason,
        details = details or {}
    }

    if type(LogAction) == 'function' then
        pcall(function()
            LogAction(identifier, playerName, action, tostring(src), playerName, payload)
        end)
        return
    end

    if MySQL and MySQL.insert then
        pcall(function()
            MySQL.insert([[
                INSERT INTO lyxpanel_logs (admin_id, admin_name, action, target_id, target_name, details)
                VALUES (?, ?, ?, ?, ?, ?)
            ]], {
                identifier,
                playerName,
                action,
                tostring(src),
                playerName,
                json.encode(payload)
            })
        end)
    end
end

local function _ForwardDetection(src, detectionType, details)
    if not (LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable()) then
        return
    end
    if not exports['lyx-guard'] or not exports['lyx-guard'].LogDetection then
        return
    end

    pcall(function()
        exports['lyx-guard']:LogDetection(src, detectionType, details or {}, nil, 'flagged')
    end)
end

local function _TrackRateLimit(src, cfg)
    local now = GetGameTimer()
    local window = FirewallState.windows[src]
    if not window or (now - window.startMs) > cfg.windowMs then
        window = { startMs = now, count = 0 }
        FirewallState.windows[src] = window
    end

    window.count = window.count + 1
    return window.count > cfg.maxEventsPerWindow, window.count
end

local function _InspectPayloadValue(value, depth, cfg, stats)
    if stats.invalidReason then return end

    if depth > cfg.maxDepth then
        stats.invalidReason = 'payload_too_deep'
        return
    end

    local t = type(value)
    if t == 'string' then
        if #value > cfg.maxStringLen then
            stats.invalidReason = 'payload_string_too_long'
            stats.meta = { stringLen = #value, maxStringLen = cfg.maxStringLen }
        end
        return
    end

    if t == 'number' or t == 'boolean' or t == 'nil' then
        return
    end

    if t == 'table' then
        local localKeyCount = 0
        for k, v in pairs(value) do
            localKeyCount = localKeyCount + 1
            stats.totalKeys = stats.totalKeys + 1

            if localKeyCount > cfg.maxKeysPerTable or stats.totalKeys > cfg.maxTotalKeys then
                stats.invalidReason = 'payload_too_many_keys'
                stats.meta = {
                    localKeyCount = localKeyCount,
                    maxKeysPerTable = cfg.maxKeysPerTable,
                    totalKeys = stats.totalKeys,
                    maxTotalKeys = cfg.maxTotalKeys
                }
                return
            end

            local keyType = type(k)
            if keyType ~= 'string' and keyType ~= 'number' then
                stats.invalidReason = 'payload_bad_key_type'
                stats.meta = { keyType = keyType }
                return
            end

            _InspectPayloadValue(v, depth + 1, cfg, stats)
            if stats.invalidReason then return end
        end
        return
    end

    stats.invalidReason = 'payload_bad_value_type'
    stats.meta = { valueType = t }
end

local function _ValidatePayload(eventData, cfg)
    if eventData == nil then
        return true, nil, nil
    end

    if type(eventData) ~= 'table' then
        return false, 'payload_not_table', { payloadType = type(eventData) }
    end

    local argCount = _GetEffectiveArgCount(eventData)
    if argCount > cfg.maxArgs then
        return false, 'payload_too_many_args', { argCount = argCount, maxArgs = cfg.maxArgs }
    end

    local stats = {
        invalidReason = nil,
        meta = nil,
        totalKeys = 0
    }

    for i = 1, argCount do
        _InspectPayloadValue(eventData[i], 1, cfg, stats)
        if stats.invalidReason then
            local meta = stats.meta or {}
            meta.argIndex = i
            return false, stats.invalidReason, meta
        end
    end

    return true, nil, nil
end

local function _TypeMatches(value, expected)
    local actual = type(value)
    if type(expected) == 'string' then
        return actual == expected
    end

    if type(expected) == 'table' then
        for _, t in ipairs(expected) do
            if actual == t then
                return true
            end
        end
        return false
    end

    return true
end

local function _IsBoolLike(value)
    local t = type(value)
    if t == 'boolean' then
        return true
    end
    if t == 'number' then
        return value == 0 or value == 1
    end
    if t == 'string' then
        local s = value:lower():gsub('%s+', '')
        return s == 'true' or s == 'false' or s == '1' or s == '0' or s == 'yes' or s == 'no' or s == 'on' or s == 'off'
    end
    return false
end

local function _ValidateSchema(eventName, eventData, cfg)
    if cfg.schemaValidation ~= true then
        return true, nil, nil
    end

    local schema = cfg.schemas and cfg.schemas[eventName]
    if type(schema) ~= 'table' then
        return true, nil, nil
    end

    if type(eventData) ~= 'table' then
        return false, 'schema_payload_not_table', { payloadType = type(eventData) }
    end

    local argCount = _GetEffectiveArgCount(eventData)
    local minArgs = tonumber(schema.minArgs)
    local maxArgs = tonumber(schema.maxArgs)

    if minArgs and argCount < minArgs then
        return false, 'schema_too_few_args', { argCount = argCount, minArgs = minArgs }
    end

    if maxArgs and argCount > maxArgs then
        return false, 'schema_too_many_args', { argCount = argCount, maxArgs = maxArgs }
    end

    local types = schema.types
    if type(types) == 'table' then
        for rawIndex, expectedType in pairs(types) do
            local idx = tonumber(rawIndex)
            if idx and idx >= 1 then
                local value = eventData[idx]
                if not _TypeMatches(value, expectedType) then
                    return false, 'schema_bad_type', {
                        argIndex = idx,
                        expected = expectedType,
                        actual = type(value)
                    }
                end
            end
        end
    end

    local numberRanges = schema.numberRanges
    if type(numberRanges) == 'table' then
        for rawIndex, rules in pairs(numberRanges) do
            local idx = tonumber(rawIndex)
            if idx and idx >= 1 and type(rules) == 'table' then
                local value = eventData[idx]
                if value ~= nil then
                local num = tonumber(value)
                if not num then
                    return false, 'schema_number_expected', {
                        argIndex = idx,
                        actual = type(value)
                    }
                end

                if rules.integer == true and math.floor(num) ~= num then
                    return false, 'schema_integer_expected', {
                        argIndex = idx,
                        value = num
                    }
                end

                local minV = tonumber(rules.min)
                local maxV = tonumber(rules.max)
                if minV and num < minV then
                    return false, 'schema_number_too_small', { argIndex = idx, value = num, min = minV }
                end
                if maxV and num > maxV then
                    return false, 'schema_number_too_large', { argIndex = idx, value = num, max = maxV }
                end
                end
            end
        end
    end

    local stringRules = schema.stringRules
    if type(stringRules) == 'table' then
        for rawIndex, rules in pairs(stringRules) do
            local idx = tonumber(rawIndex)
            if idx and idx >= 1 and type(rules) == 'table' then
                local value = eventData[idx]
                if value ~= nil and type(value) ~= 'string' then
                    return false, 'schema_string_expected', {
                        argIndex = idx,
                        actual = type(value)
                    }
                end

                if type(value) == 'string' then
                    local s = value
                    if rules.trim == true then
                        s = s:match('^%s*(.-)%s*$') or s
                    end

                    local minLen = tonumber(rules.minLen)
                    local maxLen = tonumber(rules.maxLen)
                    if minLen and #s < minLen then
                        return false, 'schema_string_too_short', { argIndex = idx, len = #s, minLen = minLen }
                    end
                    if maxLen and #s > maxLen then
                        return false, 'schema_string_too_long', { argIndex = idx, len = #s, maxLen = maxLen }
                    end
                end
            end
        end
    end

    local enums = schema.enums
    if type(enums) == 'table' then
        for rawIndex, allowed in pairs(enums) do
            local idx = tonumber(rawIndex)
            if idx and idx >= 1 and type(allowed) == 'table' then
                local value = eventData[idx]
                if value ~= nil then
                    local key = tostring(value or '')
                    local keyLower = key:lower()
                    if allowed[key] ~= true and allowed[keyLower] ~= true then
                        return false, 'schema_enum_not_allowed', {
                            argIndex = idx,
                            value = key
                        }
                    end
                end
            end
        end
    end

    local tableRules = schema.tableRules
    if type(tableRules) == 'table' then
        for rawIndex, rules in pairs(tableRules) do
            local idx = tonumber(rawIndex)
            if idx and idx >= 1 and type(rules) == 'table' then
                local tableValue = eventData[idx]
                if tableValue ~= nil then
                    if type(tableValue) ~= 'table' then
                        return false, 'schema_table_expected', {
                            argIndex = idx,
                            actual = type(tableValue)
                        }
                    end

                    local maxKeys = tonumber(rules.maxKeys)
                    if maxKeys and maxKeys >= 0 then
                        local keyCount = 0
                        for _ in pairs(tableValue) do
                            keyCount = keyCount + 1
                        end
                        if keyCount > maxKeys then
                            return false, 'schema_table_too_many_keys', {
                                argIndex = idx,
                                keyCount = keyCount,
                                maxKeys = maxKeys
                            }
                        end
                    end

                    local fields = rules.fields
                    if type(fields) == 'table' then
                        for fieldName, fieldRule in pairs(fields) do
                            if type(fieldRule) == 'table' then
                                local fieldValue = tableValue[fieldName]
                                if fieldValue == nil then
                                    if fieldRule.required == true then
                                        return false, 'schema_table_field_missing', {
                                            argIndex = idx,
                                            field = tostring(fieldName)
                                        }
                                    end
                                else
                                    local expectedType = fieldRule.type or fieldRule.types
                                    if expectedType ~= nil and not _TypeMatches(fieldValue, expectedType) then
                                        return false, 'schema_table_field_bad_type', {
                                            argIndex = idx,
                                            field = tostring(fieldName),
                                            expected = expectedType,
                                            actual = type(fieldValue)
                                        }
                                    end

                                    if fieldRule.boolLike == true and not _IsBoolLike(fieldValue) then
                                        return false, 'schema_table_field_bad_bool', {
                                            argIndex = idx,
                                            field = tostring(fieldName),
                                            actual = type(fieldValue)
                                        }
                                    end

                                    if fieldRule.integer == true or fieldRule.min ~= nil or fieldRule.max ~= nil then
                                        local num = tonumber(fieldValue)
                                        if not num then
                                            return false, 'schema_table_field_number_expected', {
                                                argIndex = idx,
                                                field = tostring(fieldName),
                                                actual = type(fieldValue)
                                            }
                                        end
                                        if fieldRule.integer == true and math.floor(num) ~= num then
                                            return false, 'schema_table_field_integer_expected', {
                                                argIndex = idx,
                                                field = tostring(fieldName),
                                                value = num
                                            }
                                        end
                                        local minV = tonumber(fieldRule.min)
                                        local maxV = tonumber(fieldRule.max)
                                        if minV and num < minV then
                                            return false, 'schema_table_field_too_small', {
                                                argIndex = idx,
                                                field = tostring(fieldName),
                                                value = num,
                                                min = minV
                                            }
                                        end
                                        if maxV and num > maxV then
                                            return false, 'schema_table_field_too_large', {
                                                argIndex = idx,
                                                field = tostring(fieldName),
                                                value = num,
                                                max = maxV
                                            }
                                        end
                                    end

                                    local minLen = tonumber(fieldRule.minLen)
                                    local maxLen = tonumber(fieldRule.maxLen)
                                    if minLen or maxLen then
                                        if type(fieldValue) ~= 'string' then
                                            return false, 'schema_table_field_string_expected', {
                                                argIndex = idx,
                                                field = tostring(fieldName),
                                                actual = type(fieldValue)
                                            }
                                        end
                                        if minLen and #fieldValue < minLen then
                                            return false, 'schema_table_field_string_too_short', {
                                                argIndex = idx,
                                                field = tostring(fieldName),
                                                len = #fieldValue,
                                                minLen = minLen
                                            }
                                        end
                                        if maxLen and #fieldValue > maxLen then
                                            return false, 'schema_table_field_string_too_long', {
                                                argIndex = idx,
                                                field = tostring(fieldName),
                                                len = #fieldValue,
                                                maxLen = maxLen
                                            }
                                        end
                                    end

                                    local fieldEnums = fieldRule.enums
                                    if type(fieldEnums) == 'table' then
                                        local key = tostring(fieldValue or '')
                                        local keyLower = key:lower()
                                        if fieldEnums[key] ~= true and fieldEnums[keyLower] ~= true then
                                            return false, 'schema_table_field_enum_not_allowed', {
                                                argIndex = idx,
                                                field = tostring(fieldName),
                                                value = key
                                            }
                                        end
                                    end
                                end
                            end
                        end

                        if rules.allowExtraKeys ~= true then
                            for key in pairs(tableValue) do
                                if fields[key] == nil then
                                    return false, 'schema_table_extra_key', {
                                        argIndex = idx,
                                        field = tostring(key)
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return true, nil, nil
end

local function _PunishSpoofer(src, cfg, eventName, reason, extra)
    local now = GetGameTimer()
    local last = FirewallState.punishCooldown[src] or 0
    if (now - last) < cfg.punishCooldownMs then
        return
    end
    FirewallState.punishCooldown[src] = now

    local fullReason = ('%s | event=%s | reason=%s'):format(cfg.banReason, tostring(eventName), tostring(reason))
    local banned = false

    if cfg.permabanOnNoAccess and LyxPanel and LyxPanel.IsLyxGuardAvailable and LyxPanel.IsLyxGuardAvailable() then
        if exports['lyx-guard'] and exports['lyx-guard'].BanPlayer then
            local ok, result = pcall(function()
                return exports['lyx-guard']:BanPlayer(src, fullReason, cfg.banDuration, cfg.banBy)
            end)
            banned = ok and result ~= false
        end
    end

    _ForwardDetection(src, 'lyxpanel_admin_event_spoof', {
        event = eventName,
        reason = reason,
        extra = extra or {},
        banned = banned
    })

    if not banned and cfg.permabanOnNoAccess then
        DropPlayer(src, 'LyxPanel Security: ' .. fullReason)
    end
end

AddEventHandler('__cfx_internal:serverEventTriggered', function(eventName, eventData)
    local src = source
    if not src or src <= 0 then return end
    if type(eventName) ~= 'string' or eventName == '' then return end

    local cfg = _GetCfg()
    if cfg.enabled ~= true then return end
    local eventRule = _GetEventRule(eventName, cfg)
    if not eventRule then return end
    local isActionEvent = eventRule.isAction == true
    local isSchemaOnlyEvent = eventRule.schemaOnly == true

    if isSchemaOnlyEvent then
        local payloadOk, payloadReason, payloadMeta = _ValidatePayload(eventData, cfg)
        if not payloadOk then
            CancelEvent()
            _LogSecurity(src, 'PANEL_EVENT_PAYLOAD', eventName, payloadReason, {
                source = src,
                payloadMeta = payloadMeta
            })
            return
        end

        local schemaOk, schemaReason, schemaMeta = _ValidateSchema(eventName, eventData, cfg)
        if not schemaOk then
            CancelEvent()
            _LogSecurity(src, 'PANEL_EVENT_SCHEMA', eventName, schemaReason, {
                source = src,
                schemaMeta = schemaMeta
            })
        end
        return
    end

    local accessReady = _CanTrustAccessCheck()
    local hasPanelAccess, group = false, nil
    if accessReady and type(HasPanelAccess) == 'function' then
        hasPanelAccess, group = HasPanelAccess(src)
    end
    local hasRequiredPermission = _HasRequiredPermission(src, eventRule)

    if not accessReady then
        CancelEvent()
        _LogSecurity(src, 'ADMIN_EVENT_BLOCKED', eventName, 'access_layer_not_ready', {})
        return
    end

    if isActionEvent and cfg.strictAllowlist and not _IsAllowlisted(eventName) then
        CancelEvent()
        local details = { group = group, source = src }
        _LogSecurity(src, 'ADMIN_EVENT_BLOCKED', eventName, 'event_not_allowlisted', details)
        _ForwardDetection(src, 'lyxpanel_admin_event_not_allowlisted', {
            event = eventName,
            group = group
        })

        if not hasPanelAccess then
            _PunishSpoofer(src, cfg, eventName, 'event_not_allowlisted', details)
        elseif cfg.notifyPlayer then
            TriggerClientEvent('lyxpanel:notify', src, 'error', 'Evento admin bloqueado por firewall')
        end
        return
    end

    local missingPanelAccess = eventRule.requirePanelAccess == true and not hasPanelAccess
    local missingPermission = not hasRequiredPermission
    if missingPanelAccess or missingPermission then
        CancelEvent()
        local reason = missingPanelAccess and 'no_panel_access' or 'no_required_permission'
        local details = {
            group = group,
            source = src,
            requiredPermission = eventRule.requiredPermission,
            missingPanelAccess = missingPanelAccess,
            missingPermission = missingPermission
        }
        _LogSecurity(src, 'ADMIN_EVENT_SPOOF', eventName, reason, details)

        if eventRule.punishNoAccess ~= false then
            _PunishSpoofer(src, cfg, eventName, reason, details)
        elseif eventRule.notifyPlayer then
            TriggerClientEvent('lyxpanel:notify', src, 'error', 'Acceso denegado por firewall')
        end
        return
    end

    if eventRule.requireActiveSession == true and not _HasActivePanelSession(src, cfg) then
        CancelEvent()
        local details = {
            group = group,
            source = src,
            ttlMs = cfg.sessionTtlMs
        }
        _LogSecurity(src, 'ADMIN_EVENT_SESSION', eventName, 'panel_session_required', details)
        _ForwardDetection(src, 'lyxpanel_admin_event_no_session', {
            event = eventName,
            group = group,
            ttlMs = cfg.sessionTtlMs
        })
        if eventRule.notifyPlayer then
            TriggerClientEvent('lyxpanel:notify', src, 'error', 'Accion bloqueada: abre el panel nuevamente')
        end
        return
    end

    local securityOk, securityReason, securityMeta = _ValidateActionSecurity(src, eventName, eventData, cfg, eventRule)
    if not securityOk then
        CancelEvent()

        local details = {
            group = group,
            source = src,
            securityReason = securityReason,
            securityMeta = securityMeta
        }

        _LogSecurity(src, 'ADMIN_EVENT_SECURITY', eventName, securityReason, details)

        local detectionType = 'lyxpanel_admin_event_token'
        if securityReason == 'security_nonce_replay' then
            detectionType = 'lyxpanel_admin_event_replay'
        end

        _ForwardDetection(src, detectionType, {
            event = eventName,
            group = group,
            reason = securityReason,
            meta = securityMeta
        })

        local shouldPunish = (
            securityReason == 'security_nonce_replay' or
            securityReason == 'security_token_mismatch'
        )
        if shouldPunish and eventRule.punishNoAccess ~= false then
            _PunishSpoofer(src, cfg, eventName, securityReason, details)
        elseif eventRule.notifyPlayer then
            TriggerClientEvent('lyxpanel:notify', src, 'error', 'Accion bloqueada: sesion segura invalida')
        end
        return
    end

    if type(TouchPanelSession) == 'function' and (isActionEvent or eventRule.requireActiveSession == true) then
        TouchPanelSession(src)
    end

    local limited, count = _TrackRateLimit(src, cfg)
    if limited then
        CancelEvent()
        local details = {
            group = group,
            count = count,
            maxEventsPerWindow = cfg.maxEventsPerWindow,
            windowMs = cfg.windowMs
        }
        _LogSecurity(src, 'ADMIN_EVENT_RATE_LIMIT', eventName, 'rate_limited', details)
        _ForwardDetection(src, 'lyxpanel_admin_event_rate_limit', {
            event = eventName,
            group = group,
            count = count,
            limit = cfg.maxEventsPerWindow
        })
        if eventRule.notifyPlayer then
            TriggerClientEvent('lyxpanel:notify', src, 'error', 'Rate limit de eventos admin excedido')
        end
        return
    end

    local payloadOk, payloadReason, payloadMeta = _ValidatePayload(eventData, cfg)
    if not payloadOk then
        CancelEvent()
        local details = {
            group = group,
            payloadReason = payloadReason,
            payloadMeta = payloadMeta
        }
        _LogSecurity(src, 'ADMIN_EVENT_PAYLOAD', eventName, payloadReason, details)
        _ForwardDetection(src, 'lyxpanel_admin_event_payload', {
            event = eventName,
            group = group,
            reason = payloadReason,
            meta = payloadMeta
        })
        if eventRule.notifyPlayer then
            TriggerClientEvent('lyxpanel:notify', src, 'error', 'Payload invalido en evento protegido')
        end
        return
    end

    local schemaOk, schemaReason, schemaMeta = _ValidateSchema(eventName, eventData, cfg)
    if not schemaOk then
        CancelEvent()
        local details = {
            group = group,
            schemaReason = schemaReason,
            schemaMeta = schemaMeta
        }
        _LogSecurity(src, 'ADMIN_EVENT_SCHEMA', eventName, schemaReason, details)
        _ForwardDetection(src, 'lyxpanel_admin_event_schema', {
            event = eventName,
            group = group,
            reason = schemaReason,
            meta = schemaMeta
        })
        if eventRule.notifyPlayer then
            TriggerClientEvent('lyxpanel:notify', src, 'error', 'Payload fuera de schema permitido')
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    FirewallState.windows[src] = nil
    FirewallState.punishCooldown[src] = nil
end)

print('^2[LyxPanel]^7 admin event firewall loaded')
