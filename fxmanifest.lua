--[[
    ██╗  ██╗   ██╗██╗  ██╗    ██████╗  █████╗ ███╗   ██╗███████╗██╗
    ██║  ╚██╗ ██╔╝╚██╗██╔╝    ██╔══██╗██╔══██╗████╗  ██║██╔════╝██║
    ██║   ╚████╔╝  ╚███╔╝     ██████╔╝███████║██╔██╗ ██║█████╗  ██║
    ██║    ╚██╔╝   ██╔██╗     ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║
    ███████╗██║   ██╔╝ ██╗    ██║     ██║  ██║██║ ╚████║███████╗███████╗
    ╚══════╝╚═╝   ╚═╝  ╚═╝    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝

    LyxPanel - Premium Admin Panel for FiveM/ESX
    Version: 2.0.0
    Author: LyxDev
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lyx-panel'
author 'LyxDev'
description 'Premium Admin Panel for FiveM/ESX Servers - Complete Edition'
version '4.5.0'

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
    'shared/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- Load order is important: bootstrap/migrations/perms first, then core, then feature modules.
    'server/bootstrap.lua',
    'server/migrations.lua',
    'server/permissions_store.lua',
    'server/access_store.lua',
    'server/main.lua',
    'server/event_firewall.lua',
    'server/actions.lua',
    'server/actions_extended.lua',
    'server/features_v45.lua',
    'server/reports.lua',
    'server/staff_commands.lua'
}

client_scripts {
    'client/*.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/img/*.png',
    'html/fonts/*'
}

dependencies {
    'es_extended',
    'oxmysql'
}
