# LyxPanel - Instalacion y Configuracion (Servidor)

Este documento explica como instalar y configurar `lyx-panel` de forma segura en un servidor FiveM/ESX.

Recomendacion fuerte: correr **`lyx-panel` + `lyx-guard`** juntos.
Si falta `lyx-guard`, LyxPanel sigue funcionando como panel in-game, pero perdes cobertura de seguridad (anti-spoof, sancion automatica, evidencia/timeline, etc).

## 1) Requisitos
- FiveM (artefacto actualizado).
- `es_extended` (ESX).
- `oxmysql`.
- Recomendado: `lyx-guard`.

## 2) Instalacion (archivos)
1. Copiar carpeta `lyx-panel` a:
   - `resources/[local]/lyx-panel`
2. Copiar tambien `lyx-guard` (recomendado) a:
   - `resources/[local]/lyx-guard`

## 3) server.cfg (orden recomendado)
El orden importa para DB/framework e integracion cruzada:

```cfg
ensure oxmysql
ensure es_extended

ensure lyx-guard
ensure lyx-panel
```

## 4) Base de datos
LyxPanel aplica migraciones versionadas al iniciar.
No necesitas ejecutar SQL manual (salvo que quieras auditar tablas).

Puntos a revisar:
- `oxmysql` conectando OK (host/user/pass/database).
- Permisos del usuario MySQL: `CREATE`, `ALTER`, `INDEX`, `INSERT`, `UPDATE`, `SELECT`.

Tablas principales (resumen):
- `lyxpanel_*` (logs, reports, tickets, bans/acciones, presets).
- `lyxpanel_schema_migrations` (versionado de migraciones).

## 5) Configuracion basica (defaults)
Archivo: `config.lua`

### 5.1 Abrir panel
```lua
Config.OpenCommand = 'lyxpanel'
Config.OpenKey = 'F6' -- default actual en config.lua
```

Recomendacion:
- usar un comando y una tecla que no choque con otros recursos.

### 5.2 Perfil runtime
```lua
Config.RuntimeProfile = 'default'
```

Perfiles disponibles:
- `rp_light`: minimiza falsos positivos (mas tolerante).
- `production_high_load`: recomendado si tu server tiene picos de eventos altos.
- `hostile`: mas cerrado (spoof/flood).

### 5.3 Seguridad: firewall de eventos admin
LyxPanel protege eventos criticos con:
- permiso
- rate-limit
- schema validation
- token + nonce + anti-replay (acciones `lyxpanel:action:*`)

Defaults recomendados:
```lua
Config.Security.adminEventFirewall.enabled = true
Config.Security.adminEventFirewall.requireActiveSession = true
```

En modo `hostile` se recomienda fail-closed:
```lua
Config.Security.adminEventFirewall.sessionStateFailOpen = false
```

## 6) Permisos / roles (como dar acceso)
LyxPanel soporta permisos granulares y una UI para administrarlos.

Recomendacion de roles tipicos:
- owner/master: todo
- admin: moderacion + economia + vehiculos + bans
- mod: moderacion limitada
- helper: tickets/reportes

Permisos clave (ejemplos):
- `canBan`, `canUnban`
- `canWipePlayer` (alto riesgo)
- `canManageTickets`
- `canUseTickets`

Buenas practicas:
- no des `canWipePlayer` a rangos bajos
- habilita dry-run para acciones destructivas cuando sea posible
- exige motivo obligatorio en acciones criticas

## 7) Tickets (soporte)
Jugadores:
- `/ticket asunto | mensaje`
- `/ticket mensaje`

Staff:
- UI -> **Tickets**: asignar, responder, cerrar, reabrir

Defaults de seguridad:
- rate-limit para evitar spam
- limites de longitud en subject/mensaje/respuesta

## 8) Integracion con LyxGuard (dependencia cruzada)
Si `lyx-guard` esta activo:
- se mejora la respuesta a intentos de spoof de eventos admin
- hay mejor telemetria y correlacion en auditoria

Si `lyx-guard` NO esta activo:
- LyxPanel funciona, pero ciertas protecciones y escalados automaticos se degradan.
- el panel puede mostrar advertencias de integracion.

## 9) Troubleshooting rapido
### No abre el panel
- revisar `Config.OpenCommand` y `Config.OpenKey`
- revisar permisos del jugador
- revisar NUI (si otro recurso bloquea focus)

### Acciones bloqueadas por firewall
- revisar rate-limits y schema validation (payload invalido)
- en `hostile`, validar sesion activa (fail-closed)

### No aparecen tickets/logs
- revisar DB (oxmysql)
- revisar migraciones y permisos MySQL

## 10) Checklist de seguridad recomendada (produccion)
- `Config.Security.adminEventFirewall.enabled = true`
- `Config.Security.adminEventFirewall.requireActiveSession = true`
- `lyx-guard` activo y configurado
- permisos granulares (no roles "todo o nada")
- revisar logs/auditoria post deploy

