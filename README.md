# LyxPanel

Panel de administracion para FiveM (ESX), con permisos granulares, auditoria avanzada y hardening de eventos criticos.

## Estado
- Proyecto activo
- Idioma principal: Espanol
- Licencia: MIT

## Caracteristicas principales
- Panel NUI con secciones operativas (jugadores, economia, vehiculos, reportes, permisos).
- Matriz de permisos por rol y por usuario, editable desde panel.
- Auditoria con filtros (admin, target, accion, fechas) y export JSON/CSV.
- Integracion con LyxGuard para telemetria y endurecimiento.
- Sistema de sesion segura para eventos admin (token + nonce + anti-replay).
- Validacion estricta de payload y rate-limit por accion sensible.
- Acciones con `dry-run` para operaciones destructivas.

## Requisitos
- FiveM server (ESX).
- `es_extended`
- `oxmysql`
- Opcional recomendado: `lyx-guard`

## Instalacion
1. Copiar `lyx-panel` a `resources/[local]/lyx-panel`.
2. Configurar `server.cfg`:
```cfg
ensure oxmysql
ensure es_extended
ensure lyx-panel
```
3. Reiniciar servidor.
4. Confirmar en consola que migraciones y callbacks cargaron correctamente.

## Configuracion rapida
- Archivo principal: `config.lua`
- Comando/apertura:
```lua
Config.OpenCommand = 'lyxpanel'
Config.OpenKey = 'F7'
```
- Seguridad de eventos:
```lua
Config.EventFirewall = {
  enabled = true
}
```

## Modelo de seguridad
- El servidor es autoridad para todas las acciones.
- Cada accion critica debe pasar por:
  - permiso
  - rate-limit
  - schema validation
  - validacion de sesion segura (token/nonce) cuando aplica

## Estructura
- `client/` puente NUI y logica cliente.
- `server/` acciones admin, permisos, reportes, firewall, migraciones.
- `html/` interfaz (HTML/CSS/JS).
- `shared/` utilidades comunes.

## Contribuir
Revisar:
- `CONTRIBUTING.md`
- `SECURITY.md`

## Licencia
MIT. Ver `LICENSE`.

