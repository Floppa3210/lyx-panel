# LyxPanel - Comparaciones y Alcance

Este documento compara el enfoque de LyxPanel con:
- paneles open source 
- paneles/anticheats de pago tipo "suite" (web + licencias + ecommerce)
- enfoque de anticheats conocidos (referencia: FiveGuard y similares)

## 0) Matriz comparativa (10 admin panels vs LyxPanel)

Notas:
- Esta tabla mezcla (a) info publica y (b) observaciones de ejemplos locales.
- "RIESGO" significa: en ejemplos locales/descargas se detectaron patrones peligrosos (loader/exec remoto, ofuscacion, URLs raras). No es un veredicto del upstream oficial.

| Panel | Tipo | Permisos granulares (UI) | Auditoria/export | Hardening eventos (schema/rate/token) | RIESGO (ejemplo local) | Nota rapida |
|---|---|---|---|---|---|---|
| **LyxPanel (este repo)** | OSS | SI | SI (export) | SI (token+nonce+schema+rate) | NO | In-game NUI, pensado para correr con LyxGuard |
| txAdmin | Oficial | PARCIAL | PARCIAL | ? | NO | Herramienta oficial (no es panel NUI ESX) |
| EasyAdmin | OSS | PARCIAL | PARCIAL | ? | SI | En ejemplos locales se vio loader/exec remoto |
| vMenu | OSS | NO | PARCIAL | ? | ? | Menu popular (no enfocado a auditoria fuerte) |
| MenuV | OSS | n/a | n/a | n/a | ? | Framework UI, no panel completo |
| esx_adminmode | OSS | NO | PARCIAL | ? | SI | En ejemplos locales se vio loader/exec remoto |
| zAdmin-esx | OSS | PARCIAL | PARCIAL | ? | SI | En ejemplos locales se vio loader/exec remoto |
| nova_adminmenu | OSS | PARCIAL | PARCIAL | ? | ? | Admin menu general |
| flight_admin | OSS | PARCIAL | PARCIAL | ? | ? | Admin menu general |
| dolu_tool | OSS | PARCIAL | PARCIAL | ? | ? | Herramienta general (version checks) |
| rw-adminmenu | OSS | PARCIAL | PARCIAL | ? | SI | En ejemplos locales se vio fetch remoto (version/json) |

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

Observacion basada en nuestro scan local (carpetas de ejemplos):
- se detectaron decenas de coincidencias HIGH asociadas a patrones de loader/exec remoto
- tambien hubo muchos matches MED/LOW de ofuscacion, URLs sospechosas y code smells

Numeros (scan local):
- archivos marcados: 147
- coincidencias HIGH: 106
- coincidencias MED: 821
- coincidencias LOW: 106

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

## 7) Referencias (lectura opcional)
- FiveGuard (safe events): https://docs.fiveguard.net/safe-events/manual-safe-events
- Tokenizacion open source (idea similar): https://github.com/BrunoTheDev/salty_tokenizer

