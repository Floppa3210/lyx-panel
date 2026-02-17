# Contribuir a LyxPanel

Gracias por colaborar.

## Flujo recomendado
1. Crear rama desde `main`.
2. Separar cambios por tema (seguridad, UI, permisos, auditoria).
3. Validar localmente antes de abrir PR.
4. Abrir PR con contexto tecnico claro.

## Reglas de calidad
- Todo evento critico debe validar: permiso, rate-limit, schema payload y sesion segura (token/nonce) cuando aplique.
- No duplicar utilidades; reutilizar `shared/`.
- Mantener naming consistente y mensajes claros para operadores.
- No introducir rutas de ejecucion dinamica ni callbacks inseguros.

## Que incluir en el PR
- Problema y objetivo.
- Riesgos/regresiones posibles.
- Archivos tocados.
- Pasos de prueba (incluyendo casos de permiso denegado y payload invalido).

## Alcance recomendado
Se aceptan mejoras de:
- seguridad de eventos
- auditoria y trazabilidad
- UX del panel y estabilidad NUI
- permisos por rol/usuario
