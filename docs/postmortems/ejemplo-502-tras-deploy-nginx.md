# Postmortem — 502 en `/quotes` tras un deploy de Nginx


- **Fecha:** 2026-11-23
- **Duración:** 14:05 – 14:19 UTC
- **Severidad:** SEV2
- **Responsable del incidente:** `@georguiazel`
- **Estado:** cerrado

## Qué pasó

Un cambio en `helm/nginx/values.yaml` cambió el `upstream` de `quotes-api:80` a `quotes-api:8080`, un puerto en el que el Service no escucha. El deploy terminó en verde porque el `/healthz` de Nginx responde sin consultar a la API, así que tanto `--atomic` como el health check del Load Balancer dieron los pods por sanos. Durante 14 minutos, toda request a `/quotes` devolvió 502, mientras `/healthz` seguía respondiendo 200.

## Impacto

| | |
|---|---|
| Endpoints afectados | `GET /quotes`, `POST /quotes` y `/health` |
| Requests con error | ~2 900, 100% de las requests a la API en la ventana |
| Tiempo sin servicio | 14 min |
| Datos perdidos o inconsistentes | Ninguno; las escrituras fallaron antes de llegar a Mongo |
| SLO consumido | ~32% del error budget mensual de disponibilidad |

## Timeline

| Hora | Evento |
|---|---|
| 14:03 | Merge del cambio en `helm/nginx/values.yaml` a `main` |
| 14:05 | `helm upgrade nginx` termina bien; los pods nuevos quedan `Ready` |
| 14:06 | El smoke test del pipeline falla en `GET /health` con 502 |
| 14:07 | El uptime check falla desde dos regiones |
| 14:10 | Salta la alerta de 5xx sobre 5% y llega al correo de on-call |
| 14:12 | Los logs de Nginx muestran `connect() failed (111: Connection refused) ... upstream: "http://10.30.x.x:8080"` |
| 14:14 | `helm rollback nginx -n quotes` |
| 14:16 | Los pods nuevos quedan `Ready` y el uptime check vuelve a pasar |
| 14:19 | La tasa de 5xx vuelve a 0 y se cierra el incidente |

## Causa raíz

El disparador fue un error de tipeo en el puerto del upstream. Lo que permitió que llegara a producción y se mantuviera fue que ninguna verificación previa al tráfico real pasaba por la API:

- El `/healthz` de Nginx solo confirma que Nginx está vivo, no que puede llegar a su upstream. Es una decisión correcta para la liveness, pero dejó ciego al health check del LB ante este caso.
- `--atomic` solo revierte si los pods no llegan a `Ready`, y en este caso llegaron.
- El smoke test detectó el problema en un minuto, pero solo marca el run en rojo y no revierte nada.

## Qué funcionó

- El smoke test falló apenas terminó el deploy, antes que cualquier alerta.
- Los logs JSON de Nginx mostraron el puerto equivocado en el primer `kubectl logs`.
- El procedimiento de rollback del runbook funcionó tal como está escrito: un solo comando y dos minutos hasta la recuperación.

## Qué no funcionó

- La alerta de 5xx tardó cinco minutos en saltar por la ventana de evaluación; el aviso más temprano fue el run rojo en GitHub, que nadie estaba mirando.
- El CI validó la sintaxis con `nginx -t`, pero no que el puerto coincidiera con el del Service.

## Action items

| Acción | Tipo | Dueño | Fecha |
|---|---|---|---|
| Hacer que un smoke test fallido ejecute `helm rollback` del chart desplegado | Mitigación | `@georguiazel` | 2026-11-30 |
| Tomar el puerto del upstream del Service de `quotes-api` en lugar de un valor suelto en el chart de Nginx | Prevención | `@georguiazel` | 2026-11-30 |
| Agregar un check en CI que compare el puerto del upstream con el `service.port` de `quotes-api` | Prevención | `@georguiazel` | 2026-12-05 |
| Notificar al correo de on-call cuando falla el workflow `deploy` | Detección | `@georguiazel` | 2026-12-05 |

## Evidencia

- Run del pipeline con el smoke test fallido: `https://github.com/georguiazel/challenge-cloud-enginner/actions/runs/<id>`
- Dashboard `quotes overview`, ventana de 14:00 a 14:30 UTC
- Logs de Nginx en Logs Explorer: `resource.labels.container_name="nginx" jsonPayload.status=502`
