# LyxPanel - Config Reference

Este documento resume las opciones mas importantes de `config.lua` y sus defaults "stock".
Para detalles finos (valores por perfil/preset), usa busqueda dentro de `config.lua`.

## 1) General
- `Config.Locale` (default: `es`)
- `Config.Debug` (default: `false`)
- `Config.OpenCommand` (default: `lyxpanel`)
- `Config.OpenKey` (default: `F6`)
- `Config.RefreshInterval` (default: `5000` ms)
- `Config.RuntimeProfile` (default: `default`)

Perfiles soportados:
- `default`
- `rp_light`
- `production_high_load`
- `hostile`

## 2) Seguridad (Config.Security)
### 2.1 Denied logging
- `Config.Security.logDeniedPermissions` (default: `true`)
- `Config.Security.deniedCooldownMs` (default: `5000`)
- `Config.Security.forwardDeniedToLyxGuard` (default: `true`)

### 2.2 Admin Event Firewall (server-side)
Objeto: `Config.Security.adminEventFirewall`

Defaults clave:
- `enabled = true`
- `strictAllowlist = true`
- `validateAllLyxpanelEvents = true`
- `requireActiveSession = true`
- `sessionTtlMs = 10 * 60 * 1000`
- `sessionStateFailOpen = true` (en `hostile`, recomendado `false`)
- rate limits:
  - `maxEventsPerWindow = 240`
  - `windowMs = 10000`
- payload sanity:
  - `maxArgs = 12`
  - `maxDepth = 6`
  - `maxKeysPerTable = 96`
  - `maxTotalKeys = 512`
  - `maxStringLen = 512`
- sancion por spoof sin acceso:
  - `permabanOnNoAccess = true`
  - `banDuration = 0` (0 = permanente)
  - `punishCooldownMs = 15000`

Action security (token + nonce + replay protection):
- `actionSecurity.enabled = true`
- `tokenTtlMs = 5 * 60 * 1000`
- `nonceTtlMs = 5 * 60 * 1000`
- `maxUsedNonces = 4096`
- `maxClockSkewMs = 180000`

### 2.3 Panel session spoof
Objeto: `Config.Security.panelSessionSpoof`
- `enabled = true`
- `permaban = true`
- `banDuration = 0`
- `dropIfGuardMissing = true`

## 3) Permisos (Config.Permissions)
LyxPanel soporta un sistema mixto:
- ESX groups
- ACE permissions
- permisos por rol e individuales desde UI (persistidos en DB)

Campos importantes:
- `system` (default: `mixed`)
- `allowedGroups` (incluye `superadmin/admin/mod/helper/master/owner`)
- `acePermissions` (ej: `lyxpanel.access`, `lyxpanel.admin`)

## 4) Limites / cooldowns (ActionLimits)
Los limites se centralizan en `config.lua` y pueden cambiar por perfil.

Recomendacion:
- ajustar solo si tenes falsos positivos de rate-limit
- no desactivar el firewall

## 5) Integracion con LyxGuard
Cuando `lyx-guard` esta activo, LyxPanel puede:
- forward de intentos denegados/sospechosos
- correlacion de auditoria con detecciones del guard

## 6) Defaults recomendados por entorno (resumen)
- RP liviano: `Config.RuntimeProfile = 'rp_light'`
- Produccion con picos: `Config.RuntimeProfile = 'production_high_load'`
- Hostil (spoof/flood): `Config.RuntimeProfile = 'hostile'` + `sessionStateFailOpen = false`

