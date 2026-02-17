# LyxPanel

![LyxPanel Banner](docs/banner.svg)

Panel de administracion **open source** para FiveM/ESX. Enfoque: seguridad server-side, auditoria real, permisos granulares y UX de staff.

Este recurso esta pensado para funcionar **junto a** `lyx-guard`.
Puede correr solo, pero para seguridad y cobertura completas se recomienda tener ambos activos (y varias funciones se degradan o se deshabilitan si falta el otro).

## Tabla de contenido
1. Instalacion
2. Configuracion (defaults)
3. Seguridad (modelo y garantias)
4. Permisos
5. Tickets in-game
6. Observabilidad (logs/auditoria)
7. Perfiles de runtime
8. Troubleshooting
9. QA offline
10. Mapa del proyecto
11. Docs

## Requisitos
- FiveM (artefacto actualizado).
- `es_extended`
- `oxmysql`
- Recomendado: `lyx-guard`

## Instalacion (paso a paso)
1. Copiar carpeta `lyx-panel` a:
   - `resources/[local]/lyx-panel`
2. Asegurar orden en `server.cfg`:
```cfg
ensure oxmysql
ensure es_extended
ensure lyx-guard
ensure lyx-panel
```
3. Reiniciar el servidor.
4. Verificar consola:
   - que `oxmysql` este listo
   - que las migraciones corran sin errores (LyxPanel aplica migraciones versionadas)
   - que el firewall de eventos este activo

## Configuracion (defaults importantes)
Archivo: `config.lua`

### Acceso al panel
```lua
Config.OpenCommand = 'lyxpanel'
Config.OpenKey = 'F7'
```

### Perfil de runtime (tuning)
```lua
-- Valores: rp_light | production_high_load | hostile
Config.RuntimeProfile = 'production_high_load'
```

### Seguridad: firewall de eventos admin
Defaults (recomendados):
```lua
Config.Security.adminEventFirewall.enabled = true
Config.Security.adminEventFirewall.requireActiveSession = true
```

Modo hostil (mas cerrado):
```lua
Config.RuntimeProfile = 'hostile'

-- En hostile: si no se puede validar la sesion, se bloquea (fail-closed)
Config.Security.adminEventFirewall.sessionStateFailOpen = false
```

### Limites / cooldowns
Los cooldowns y clamps estan centralizados en `config.lua` (ActionLimits / Security.*).

## Seguridad (modelo y garantias)
Principios:
- **Server-authoritative**: el servidor decide; el cliente solo pide.
- Ninguna accion critica depende de logica cliente.
- Todo evento critico se valida con 3 capas obligatorias:
  - permiso
  - rate-limit
  - schema validation (tipo/rango/longitud/profundidad)

Anti-spoof:
- Acciones `lyxpanel:action:*` usan un envelope con `token + nonce` y **anti-replay**.
- Si un cheater intenta ejecutar un evento admin sin permisos/sesion/nonce valido, se bloquea.
- Con `lyx-guard` activo, intentos de spoof pueden escalar a sancion segun perfil.

## Permisos
LyxPanel usa permisos granulares y soporta:
- permisos por rol (role permissions)
- permisos individuales por usuario (individual permissions)
- auditoria de cambios

En el panel (UI) existe una matriz visual para editar permisos sin tocar JSON/CFG.

Permisos ejemplo:
- `canBan`, `canUnban`
- `canWipePlayer` (permiso dedicado, no reutiliza `canBan`)
- `canManageTickets` (assign/reply/close/reopen)
- `canUseTickets` (ver/listar)

## Tickets in-game
Jugadores:
- Crear ticket:
  - `/ticket asunto | mensaje`
  - o `/ticket mensaje`

Staff (UI -> pestaña Tickets):
- asignar a un admin
- responder (se guarda como historial en `admin_response`)
- cerrar / reabrir

Seguridad:
- todo el workflow de tickets pasa por `lyxpanel:action:*` (permiso + rate + schema + anti-replay)
- limites de longitud configurables

## Observabilidad (logs y auditoria)
LyxPanel registra:
- admin + accion + target + resultado
- correlation_id para trazabilidad
- export paginado desde UI en JSON/CSV (auditoria)

Integracion con LyxGuard (recomendado):
- correlacion panel + detecciones/sanciones del guard
- evidencia y timeline (si esta habilitado en guard)

## Perfiles de runtime
Valores:
- `rp_light`: tolerante, menos agresivo
- `production_high_load`: para servidores con picos altos de eventos
- `hostile`: mas cerrado, pensado para entornos con spoof/flood

Guia con valores exactos:
- `docs/operations/PRODUCCION_ALTA_CARGA.md`

## Troubleshooting (comun)
1. No abre el panel:
   - verificar `Config.OpenKey` / `Config.OpenCommand`
   - revisar permisos del jugador
2. No corren migraciones:
   - confirmar `oxmysql` antes de `lyx-panel`
   - revisar credenciales DB y logs de MySQL
3. Acciones bloqueadas por firewall:
   - revisar `Config.Security.adminEventFirewall.*`
   - en entorno hostil, validar que la sesion este activa (fail-closed)

## QA offline (antes de release)
```bash
node tools/qa/check_events.js
```

## Mapa del proyecto (estructura)
```text
lyx-panel/
  fxmanifest.lua
  config.lua
  database_extended.sql
  README.md
  LICENSE
  SECURITY.md
  CONTRIBUTING.md
  .gitignore

  client/
    main.lua
    features_v45.lua
    staff_commands.lua
    toggles.lua
    spectate.lua
    freecam.lua
    zones.lua
    client_extended.lua

  server/
    main.lua
    actions.lua
    actions_extended.lua
    event_firewall.lua
    migrations.lua
    reports.lua
    tickets.lua
    presets.lua
    permissions_store.lua
    access_store.lua
    staff_commands.lua
    bootstrap.lua
    features_v45.lua

  shared/
    lib.lua

  html/
    index.html
    css/style.css
    js/app.js
    js/app_extended.js
    vendor/fontawesome/...

  tools/
    qa/check_events.js

  docs/
    banner.svg
    operations/PRODUCCION_ALTA_CARGA.md
    pack_parity/PACK_PARITY_PASS1.md
    pack_parity/PACK_PARITY_PASS2.md
    pack_parity/PACK_PARITY_PASS3.md
    pack_parity/PACK_PARITY_PASS4.md
```

## Docs
- Perfil produccion alta carga: `docs/operations/PRODUCCION_ALTA_CARGA.md`
- Pack parity (comparativa, no SaaS): `docs/pack_parity/PACK_PARITY_PASS1.md`
- Evidencia tecnica: `docs/pack_parity/PACK_PARITY_PASS2.md`
- Brechas/riesgos: `docs/pack_parity/PACK_PARITY_PASS3.md`
- Plan de cierre: `docs/pack_parity/PACK_PARITY_PASS4.md`

## Contribuir
Toda contribucion suma:
- cambios pequenos y revisables
- cada accion nueva: permiso + rate-limit + schema + auditoria

Ver:
- `CONTRIBUTING.md`
- `SECURITY.md`

## Licencia
MIT. Ver `LICENSE`.

