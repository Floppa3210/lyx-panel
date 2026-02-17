# LyxPanel - Como Funciona (Deep Dive)

Este documento describe LyxPanel a profundidad: flujo de eventos, modelo de seguridad, sesion, anti-spoof y auditoria.

## 1) Objetivo de diseno
LyxPanel es un panel NUI in-game para administrar un servidor ESX sin exponer acciones criticas a ejecucion arbitraria desde clientes.

Principio central:
- **Server-authoritative**: el servidor valida todo.

## 2) Componentes
- NUI: `html/index.html`, `html/js/app.js`, `html/js/app_extended.js`, `html/css/style.css`
- Cliente: `client/main.lua` (puente NUI <-> servidor, no decide sanciones)
- Servidor:
  - `server/main.lua`: core, callbacks, estado de sesiones, endpoints de UI
  - `server/event_firewall.lua`: firewall de eventos y schema validation
  - `server/actions.lua`: acciones admin (`lyxpanel:action:*`)
  - `server/actions_extended.lua`: acciones extendidas con clamps/validacion
  - `server/migrations.lua`: migraciones DB versionadas
  - `server/reports.lua`: sistema de reportes
  - `server/tickets.lua`: tickets in-game
  - `server/presets.lua`: presets/builds/favoritos/historial

## 3) Flujo de datos (alto nivel)
1. Admin abre el panel (NUI).
2. NUI llama a endpoints NUI (client) y el cliente reenvia al servidor.
3. Acciones criticas se ejecutan por eventos `lyxpanel:action:*`.
4. Antes de ejecutar: firewall valida permiso + rate-limit + schema + envelope (token/nonce).
5. Se registra auditoria (DB) + correlation_id.

## 4) Modelo de seguridad
### 4.1 Regla de oro: no confiar en el cliente
El cliente puede ser:
- dumpeado
- editado
- inyectado por menus

Por eso:
- el cliente no autoriza acciones
- el servidor no acepta payloads "libres"

### 4.2 Tres capas obligatorias por evento critico
1. Permiso (rol/individual)
2. Rate-limit (cooldowns y ventanas)
3. Schema validation (tipos/rangos/longitudes/profundidad)

### 4.3 Envelope anti-spoof (token + nonce + anti-replay)
Acciones `lyxpanel:action:*` se envuelven con:
- `token` de sesion (TTL)
- `nonce` por accion (TTL corto)
- cache de nonces usados (anti-replay)

Resultado:
- si un cheater reejecuta el mismo evento (replay), se rechaza
- si intenta llamar el evento sin sesion/token valido, se rechaza

### 4.4 Fail-open vs fail-closed (sesion)
En algunos entornos, el provider de sesion puede fallar (ej. arranque parcial).

LyxPanel expone un switch:
- `sessionStateFailOpen = true`: no rompe produccion (pero es menos estricto)
- `sessionStateFailOpen = false` (recomendado en `hostile`): bloquea acciones si no puede validarse sesion

## 5) Schema validation (por que es critica)
Muchos abusos no son solo "evento sin permiso", sino payload malicioso:
- tablas profundas para reventar el handler
- strings enormes para memory/CPU
- numeros fuera de rango para glitch de economia/coords

El firewall aplica:
- limites de profundidad y keys
- max string length
- tipos esperados
- rangos min/max (clamps)

## 6) Auditoria y trazabilidad
LyxPanel registra:
- actor (admin)
- accion
- target
- resultado
- correlation_id

Esto permite:
- explicar que paso (incidente)
- auditar abuso interno (admins)
- depurar falsos positivos/negativos

## 7) Integracion con LyxGuard (por que mejora seguridad)
LyxPanel puede bloquear acciones por si mismo, pero:
- LyxGuard agrega deteccion extra de spoof (txAdmin/LyxPanel/LyxGuard)
- agrega score/riesgo y escalado
- agrega timeline/evidence para sanciones

Recomendacion:
- desplegar ambos y activar perfil consistente (`production_high_load` o `hostile`)

## 8) Consideraciones de rendimiento
Reglas:
- validar temprano (antes de entrar a acciones costosas)
- usar rate-limits por admin y por target en acciones pesadas (screenshot, wipe, etc)
- evitar spam del NUI (limitar refresh y peticiones)

## 9) Extender LyxPanel de forma segura (guia para devs)
Si agregas una accion nueva:
1. Definir permiso especifico.
2. Definir schema (tipos/rangos/longitudes).
3. Definir rate-limit (cooldown).
4. Registrar auditoria.
5. Si la accion es destructiva:
   - confirmacion fuerte
   - motivo obligatorio
   - dry-run cuando aplique

