<div align="center">

# LyxPanel

<img src="docs/banner.svg" alt="LyxPanel Banner" width="720" />

### Panel de administracion **open source** para FiveM/ESX

<p align="center">
  <strong>Server-first</strong> • <strong>Permisos granulares</strong> • <strong>Auditoria real</strong> • <strong>Anti-spoof</strong>
</p>

<p align="center">
  <a href="docs/INSTALL_SERVER.md">📦 Instalacion</a> •
  <a href="docs/DEEP_DIVE.md">🔬 Deep Dive</a> •
  <a href="docs/CONFIG_REFERENCE.md">⚙️ Config</a> •
  <a href="docs/COMPARISON.md">🆚 Comparaciones</a>
</p>

[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=for-the-badge)](LICENSE)
![FiveM](https://img.shields.io/badge/FiveM-resource-black?style=for-the-badge)
![ESX](https://img.shields.io/badge/ESX-supported-green?style=for-the-badge)
[![CI](https://img.shields.io/github/actions/workflow/status/Floppa3210/lyx-panel/qa.yml?style=for-the-badge)](https://github.com/Floppa3210/lyx-panel/actions/workflows/qa.yml)
[![Stars](https://img.shields.io/github/stars/Floppa3210/lyx-panel?style=for-the-badge&logo=github)](https://github.com/Floppa3210/lyx-panel/stargazers)

</div>

---

## Estado del proyecto
- Licencia: `MIT`
- Estado: `Activo`
- Enfoque: seguridad real del lado servidor + experiencia de staff
- Instalacion recomendada: **`lyx-panel` + `lyx-guard` juntos**

> Importante: podes ejecutar `lyx-panel` solo, pero la instalacion soportada/recomendada es tener ambos activos (`lyx-panel` + `lyx-guard`). Si falta uno, hay degradacion/inhabilitacion de features dependientes y perdes cobertura de seguridad.

## Por que existe
Muchos paneles/adminmenus de FiveM fallan en lo mas importante:
- eventos ejecutables por cualquiera (spoof)
- payloads sin validacion (tablas profundas/strings gigantes)
- permisos inconsistentes
- cero auditoria

LyxPanel esta disenado con un contrato simple:
- **el servidor valida y decide**
- **toda accion critica tiene permiso + rate-limit + schema validation**
- **las acciones admin usan token + nonce + anti-replay**
- **toda accion queda auditada**

<div align="center">

## Por que usar LyxPanel

</div>

<table>
<tr>
<td width="50%">

### Seguridad real (server-first)

```text
- Firewall de eventos (allowlist + schema + rate-limit)
- Token + nonce + anti-replay (acciones admin)
- Controles de payload (deep tables / strings enormes)
```

</td>
<td width="50%">

### Operacion de staff

```text
- Permisos por rol + por usuario (desde UI)
- Auditoria y export (JSON/CSV)
- Tickets in-game + reportes + presets
```

</td>
</tr>
</table>

## Que incluye (resumen)
- Panel NUI: jugadores, economia, vehiculos, reportes, bans, auditoria, permisos, presets.
- Permisos granulares:
  - por rol
  - por usuario (individual)
  - con auditoria de cambios
- Firewall de eventos para acciones admin:
  - allowlist
  - rate-limit
  - schema validation (tipos/rangos/longitudes/profundidad)
  - token + nonce + anti-replay
- Tickets in-game:
  - jugadores: `/ticket`
  - staff: workflow desde UI (asignar/responder/cerrar/reabrir)
- Modo simulacion (`dry-run`) para acciones destructivas.

## Instalacion rapida
1. Copiar `lyx-panel` a `resources/[local]/lyx-panel`.
2. Recomendado: copiar `lyx-guard` a `resources/[local]/lyx-guard`.
3. En `server.cfg`:
```cfg
ensure oxmysql
ensure es_extended
ensure lyx-guard
ensure lyx-panel
```
4. Reiniciar y revisar consola (migraciones + firewall).

Guia completa:
- `docs/INSTALL_SERVER.md`

## Configuracion (entry points)
Archivo: `config.lua`

Acceso al panel:
```lua
Config.OpenCommand = 'lyxpanel'
Config.OpenKey = 'F6'
```

Perfil runtime:
```lua
Config.RuntimeProfile = 'default' -- rp_light | production_high_load | hostile
```

Referencia completa de opciones:
- `docs/CONFIG_REFERENCE.md`

## Seguridad (resumen)
- Server-authoritative: nada critico se confia al cliente.
- Acciones `lyxpanel:action:*` con token + nonce + anti-replay.
- Cualquier intento de spoof de eventos admin se bloquea (y puede escalar con `lyx-guard` activo).

Detalles:
- `docs/DEEP_DIVE.md`

## Testing / QA offline
Check de cobertura de schemas/allowlists (recomendado antes de release):
```bash
node tools/qa/check_events.js
```

## Estructura del proyecto
```text
lyx-panel/
  fxmanifest.lua
  config.lua
  database_extended.sql
  README.md
  LICENSE
  SECURITY.md
  CONTRIBUTING.md

  client/         # bridge NUI <-> servidor + helpers
  server/         # firewall + acciones + migraciones + logs
  shared/         # utilidades compartidas
  html/           # UI (NUI)
  tools/qa/       # checks offline
  docs/           # documentacion
```

## Contribuir
Si queres aportar:
1. Issues y PRs son bienvenidos.
2. Toda action nueva debe incluir:
   - permiso
   - rate-limit
   - schema validation
   - auditoria

Ver:
- `CONTRIBUTING.md`
- `SECURITY.md`
