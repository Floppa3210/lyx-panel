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

## 3) Lo que vimos en ejemplos locales (adminpanel-copiar)
En varios ejemplos (de internet) se repiten patrones peligrosos:
- ejecucion dinamica de codigo (`load`, `loadstring`, `assert(load(...))`)
- codigo descargado por HTTP y ejecutado
- ofuscacion y dominios raros

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
Referencia conceptual:
- FiveGuard y anticheats similares suelen endurecer eventos y "safe events" con tokens/identidad.

Puntos comparables con LyxPanel:
- hardening de eventos admin
- tokenizacion/anti-replay
- rate-limits y controles de payload

Diferencia de arquitectura:
- LyxPanel es panel in-game con server-authority.
- La cobertura anticheat profunda y sancion escalada es rol de `lyx-guard`.

## 6) Objetivo de calidad (para mantener nivel "pro")
Para que un panel sea "pro" en un entorno hostil:
- toda accion critica debe ser auditable (quien, que, cuando, contra quien)
- toda accion debe ser server-authoritative
- no debe haber eventos sin schema
- no debe existir "bypass por evento" para cheaters (spoof)

LyxPanel asume ese contrato y delega el enforcement extra a LyxGuard cuando esta presente.

