# Postmortem — <título corto del incidente>

- **Fecha:** YYYY-MM-DD
- **Duración:** HH:MM – HH:MM UTC
- **Severidad:** SEV1 / SEV2 / SEV3
- **Responsable del incidente:** `@usuario`
- **Estado:** borrador / revisado / cerrado

## Qué pasó

Resumen en pocas líneas de lo que vieron los clientes y de lo que estaba pasando por detrás.

## Impacto

| | |
|---|---|
| Endpoints afectados | `/quotes`, `/health`, ... |
| Requests con error | N, X% del total en la ventana |
| Tiempo sin servicio o degradado | N min |
| Datos perdidos o inconsistentes | Ninguno / detalle |
| SLO consumido | X% del error budget mensual |

## Timeline

Horas en UTC, desde el primer síntoma hasta el cierre.

| Hora | Evento |
|---|---|
| HH:MM | Primer síntoma: alerta, reporte de un cliente o hallazgo en el dashboard |
| HH:MM | Se empieza a investigar |
| HH:MM | Se identifica la causa |
| HH:MM | Se aplica la mitigación: rollback, escalado, restore, ... |
| HH:MM | El servicio vuelve a la normalidad |

## Causa raíz

Qué falló y por qué. Si hubo varios factores, separar el disparador, como un deploy o un pico de tráfico, de lo que permitió que escalara, como un límite mal dimensionado, una alerta que no saltó o la falta de un índice.

## Qué funcionó

Alertas, procedimientos del runbook o automatismos que ayudaron a detectar o mitigar más rápido.

## Qué no funcionó

Lo que demoró la detección o la recuperación: falta de visibilidad, pasos del runbook desactualizados, accesos que no estaban listos.

## Action items

| Acción | Tipo | Dueño | Fecha |
|---|---|---|---|
| | Prevención / Detección / Mitigación | `@usuario` | YYYY-MM-DD |

## Evidencia

Links a los logs, al dashboard, a los runs de GitHub Actions o a los commits relacionados.
