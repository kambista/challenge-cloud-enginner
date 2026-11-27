# Runbook - quotes-api

## 1. Resumen del servicio
- **Servicio:** quotes-api | **Dueno / On-call:** Fabricio Neyra (`Fabri-99`)
- **Repo:** https://github.com/Fabri-99/challenge-cloud-enginner
- **URL publica:** https://34.110.231.216.nip.io
- **Entorno / GCP:** produccion | `kambista-quotes-reto` (`us-central1-a`)

## 2. Diagrama de arquitectura
Ver [`docs/arquitectura.md`](./arquitectura.md).

## 3. SLOs / Objetivos
- **Disponibilidad:** 99.5% mensual (health checks `/healthz` y `/health`).
- **Latencia p95:** < 500ms (Load Balancer + pruebas k6).
- **Error rate:** < 1% 5xx (Cloud Logging `namespace_name="quotes"`).

## 4. Accesos y herramientas
- **GKE:** `gcloud container clusters get-credentials kambista-gke-cluster --zone us-central1-a --project kambista-quotes-reto`
- **Logs:** `kubectl logs -n quotes -l app=quotes-api --tail=200 -f`
- **Monitoring:** Dashboard `Kambista - quotes-api GKE Overview` y Alerta `quotes-api - Alerta de Reinicio de Contenedores (CrashLoop)`.

## 5. Deploy
- **Normal:** `git push` a `main` o `feature/fabricio-neyra` ejecuta `.github/workflows/deploy.yml` (OIDC -> Docker build/push -> `kubectl apply -f k8s/` -> `kubectl set image` -> smoke test).
- **Emergencia:** `kubectl set image deployment/quotes-api quotes-api=us-central1-docker.pkg.dev/kambista-quotes-reto/quotes-api/quotes-api:<tag> -n quotes`

## 6. Rollback
```bash
kubectl rollout history deployment/quotes-api -n quotes
kubectl rollout undo deployment/quotes-api -n quotes
```
## 7. Troubleshooting
- **502 / 503:** Revisar `kubectl get pods -n quotes`, `kubectl logs <pod> -n quotes --previous`, logs de `nginx-proxy` y ping a `mongodb-0`.
- **Latencia alta:** Revisar dashboard en Cloud Monitoring, `kubectl top pods -n quotes`, `kubectl get hpa -n quotes` y posibles `429` por rate limit (`20r/s`) en Nginx.
- **HPA no escala:** Revisar `kubectl describe hpa quotes-api -n quotes` y `metrics-server` en `kube-system`.
- **Pipeline falla:** Verificar permisos `id-token: write` y condicion OIDC en GitHub Actions.
- **Mongo no persiste:** Verificar PVC `mongo-data-mongodb-0` en estado `Bound`.

## 8. Escalado
- **Vertical:** Editar `resources` en `k8s/02-quotes-api.yaml`.
- **Horizontal:** HPA automatico (2-6 replicas al 60% CPU) o `kubectl scale deployment quotes-api -n quotes --replicas=5`.
- **Cluster:** Ajustar `node_count` en `terraform/modules/gke/variables.tf` y aplicar con Terraform.

## 9. Backups y restore
- **Estrategia:** Disco `standard-rwo` (5Gi) + snapshots de disco y `mongodump --gzip --archive` (recomendado `CronJob` diario hacia GCS con retencion 30 dias).
- **Restore:** `kubectl exec -i mongodb-0 -n quotes -- mongorestore --username quotes_admin --password <PASS> --authenticationDatabase admin --drop --archive < backup.gz`

## 10. Rotacion de secretos
Crear usuario temporal en MongoDB, agregar nueva version en Secret Manager (`quotes-mongo-uri`), actualizar `mongo-secret` en `quotes`, reiniciar con `kubectl rollout restart deployment/quotes-api -n quotes` y eliminar el usuario antiguo.

## 11. Costos
- **Estimado 24/7 (`us-central1`):** ~USD 102/mes (2x `e2-medium` ~$49, HTTP(S) LB + IP ~$18.50, Cloud NAT ~$32, Disco/AR/Logs ~$2.50). Ejecutar `terraform destroy` tras la revision.

## 12. Escalamiento del incidente
Resolver con runbook (<= 30 min) -> Escalar a Tech Lead de Plataforma -> Notificar `#incidents-platform` -> Postmortem en 48h.

## 13. Postmortem template
Crear `docs/postmortems/YYYY-MM-DD-<slug>.md` con: **Que paso**, **Impacto**, **Timeline**, **Causa raiz (5 Whys)**, **Que funciono**, **Que no funciono** y **Action items**.

## 14. Contactos y escalado externo
- **Soporte GCP:** https://console.cloud.google.com/support?project=kambista-quotes-reto
- **On-call:** Fabricio Neyra (`Fabri-99`)
