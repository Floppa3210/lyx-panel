# Politica de Seguridad

## Reporte de vulnerabilidades
Si encontras una vulnerabilidad, no la publiques en un issue abierto.

Canal recomendado:
- Usar GitHub Security Advisories del repositorio.

Incluir en el reporte:
- descripcion tecnica del vector
- impacto esperado
- pasos de reproduccion
- version/commit afectado

## Alcance
Se considera vulnerabilidad, entre otros:
- bypass de permisos en acciones admin
- ejecucion de eventos criticos sin validacion de payload
- bypass de token/nonce/anti-replay
- acceso no autorizado a funciones de economia/ban/wipe

## Tiempos objetivo
- confirmacion inicial: 72 horas
- evaluacion tecnica: 7 dias
- parche inicial (si aplica): 30 dias
