-- LyxPanel - Admin Panel for FiveM/ESX

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lyx-panel'
author 'LyxDev'
description 'Panel de administracion para servidores FiveM/ESX'
version '4.5.1'

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
    'shared/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- Orden recomendado: bootstrap/migraciones/permisos, luego modulos core.
    'server/bootstrap.lua',
    'server/migrations.lua',
    'server/permissions_store.lua',
    'server/access_store.lua',
    'server/main.lua',
    'server/event_firewall.lua',
    'server/actions.lua',
    'server/actions_extended.lua',
    'server/features_v45.lua',
    'server/presets.lua',
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
    'html/vendor/fontawesome/css/*.css',
    'html/vendor/fontawesome/webfonts/*',
    'html/img/*.png',
    'html/fonts/*'
}

dependencies {
    'es_extended',
    'oxmysql'
}
