# Changelog — LyxPanel

## Hardening client-side — exports privilegiados y callbacks duplicados

Auditoría de seguridad del client-side. El server-side (permisos granulares
`HasPermission`, `HasPanelAccess` vía ACE, event firewall con allowlist + rate-limit +
validación de payload, SQL 100% parametrizado) se verificó **sólido y sin cambios**.

Los hallazgos estaban en el cliente: varios módulos exportaban funciones privilegiadas
que salteaban el control server-side (cualquier resource/executor podía invocarlas sin
abrir el panel ni tener permisos). Además, `zones.lua`/`freecam.lua` registraban callbacks
NUI que, por orden de carga alfabético, **sobrescribían** las versiones seguras de `main.lua`.

### Cambios
- **`client/zones.lua` eliminado.** Era una duplicación completa de callbacks que ya vivían
  (bien hechos) en `client/main.lua` — pero las versiones de zones eran inseguras: gate por
  `IsNuiFocused()` en vez del estado real del panel, `CleanupZone` sin clamp de radio, y
  exportaba `CleanupZone`/`TeleportToWarp`/`ScanArea` (destructivas/teleport) accesibles por
  cualquier executor. `main.lua` ya cubre todo con clamp de radio, chequeo `isOpen` y routing
  server-side (`SendSecureServerEvent`). Los warps comparten el mismo store KVP, sin pérdida.
  También arregla `spectateNearest` (la versión de zones disparaba `lyxpanel:startSpectate`,
  un evento sin handler → feature muerta; la de main.lua rutea por `lyxpanel:action:spectate`
  con gate `canSpectate`).
- **`client/toggles.lua`:** se retiraron los exports `ToggleGodmode`, `ToggleInvisible`,
  `ToggleNoclip`, `ToggleSpeedboost`, `ToggleNitro`, `ToggleVehicleGodmode`. Exponerlos daba
  godmode/noclip/invisibilidad a cualquiera vía `exports['lyx-panel']:ToggleGodmode(true)`.
  El único camino válido es el driver server-driven `lyxpanel:toggles:set`. Se conserva
  `GetToggleStates` (solo lectura).
- **`client/spectate.lua`:** se retiraron los exports `StartSpectate`/`StopSpectate`
  (`SetEntityCoords` a coords arbitrarias + invisible + invencible → teletransporte/ocultación
  vía export). El único camino válido es `lyxpanel:spectate:start` (gate `canSpectate`).
  Se conserva `IsSpectating` (solo lectura).
- **`client/freecam.lua`:** se retiró el callback NUI duplicado `toggleFreecam` (la versión
  segura vive en `main.lua`) y el export `ToggleFreecam`. Se conservan los exports de lectura.
- **`server/main.lua`:** `_ForwardPanelSessionSpoofDetection` ahora usa
  `LyxPanel.IsLyxGuardAvailable()` como guardia, por consistencia con el resto del código.

### Verificado
- Ningún consumidor externo usaba los exports retirados (grep en client/server/html).
- `instantRespawn` (staff_commands) confirmado server-authoritative: el flag de cliente es
  cosmético; el revive real solo ocurre si el server (`StaffStates.instantRespawn`, seteado
  por admin) lo autoriza. Sin cambios necesarios.
- `luac -p` OK en los archivos editados.
