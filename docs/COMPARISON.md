# LyxPanel - Comparaciones y Alcance

Este documento compara el enfoque de LyxPanel con:
- paneles open source 
- paneles/anticheats de pago tipo "suite" (web + licencias + ecommerce)
- enfoque de anticheats conocidos (referencia: FiveGuard y similares)

## 1) Alcance real de LyxPanel (que SI y que NO)
LyxPanel es un panel **in-game (NUI)**.

SI incluye:
- permisos granulares (rol + individual) desde UI
- auditoria real (logs + export)
- eventos admin endurecidos (permiso + rate + schema + token/nonce)
- tickets/reportes/presets

NO incluye (a proposito):
- SaaS web externo (Node/Express/TS) multi-tenant
- ecommerce (Stripe/PayPal), licencias, key management
- discord bot de ventas

Razon:
- esas piezas aumentan superficie de ataque y se deben aislar en un proyecto separado si alguna vez se agregan.

## 2) Diferencia clave vs paneles "clasicos" (open source)
Muchos paneles/adminmenus se basan en:
- eventos libres (sin schema)
- checks de permiso inconsistentes
- rate-limits inexistentes

LyxPanel endurece el camino critico:
- unifica el set de eventos admin en `lyxpanel:action:*`
- aplica siempre las 3 capas + envelope anti-replay
- registra auditoria por defecto

## 3) Lo que vi en ejemplos de otro github/leaks
En varios ejemplos (de internet) se repiten patrones peligrosos:
- ejecucion dinamica de codigo (`load`, `loadstring`, `assert(load(...))`)
- codigo descargado por HTTP y ejecutado
- ofuscacion y dominios raros

Conclusion practica:
- no conviene "copiar y pegar" codigo de paneles/menus publicos
- si se rescatan ideas, que sea solo UX/estructura y reescribir la logica de seguridad desde cero

LyxPanel evita eso:
- no hace exec remoto
- no hace loaders
- prefiere config local y validaciones server-side

## 4) Comparacion con suites comerciales (alto nivel)
Un pack comercial suele incluir:
- web panel externo + auth + OAuth2 Discord
- licencias/keys + binding
- global bans cross-server
- uploads/galeria de evidencia

LyxPanel se centra en:
- moderacion y administracion in-game segura
- permisos/auditoria/operacion diaria

Si en el futuro se arma un web panel externo:
- recomendado: repo separado, API segura y sin mezclar con el core del recurso.

## 5) Comparacion con FiveGuard (enfoque y conceptos)
Referencia (publica) y conceptual:
- FiveGuard y anticheats similares suelen tener un sistema de "safe events" donde el cliente adjunta un **token** a los eventos y el servidor valida ese token antes de ejecutar handlers sensibles.

Detalles publicos (resumen):
- En guias publicas de FiveGuard se describe que un "safe event" se valida usando un token que viaja dentro de los argumentos del evento (en algunos ejemplos, como ultimo argumento).
- FiveGuard expone APIs/exports para consultar tokens del jugador y registrar eventos como "safe".

Puntos comparables con LyxPanel (cuando corre junto a LyxGuard):
- hardening de eventos admin
- tokenizacion por accion + nonce + anti-replay
- rate-limits y controles de payload (schema)

Diferencia de arquitectura:
- LyxPanel es un panel in-game (NUI) y su seguridad se centra en acciones de staff.
- La cobertura anticheat profunda y sancion escalada es rol de `lyx-guard`.

Nota importante:
- Sistemas de safe-events basados en "hookear" TriggerServerEvent o auto-registrar eventos pueden generar falsos positivos si otros recursos disparan eventos legitimos sin token. El enfoque recomendado es: server-side strict + allowlist + schema + rate-limit, y usar tokens/nonce solo para acciones realmente criticas.

## 6) Objetivo de calidad (para mantener nivel "pro")
Para que un panel sea "pro" en un entorno hostil:
- toda accion critica debe ser auditable (quien, que, cuando, contra quien)
- toda accion debe ser server-authoritative
- no debe haber eventos sin schema
- no debe existir "bypass por evento" para cheaters (spoof)

LyxPanel asume ese contrato y delega el enforcement extra a LyxGuard cuando esta presente.


