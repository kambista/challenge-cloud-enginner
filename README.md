# Kambista Cloud Engineer Challenge - `quotes-api`

Infraestructura como Codigo, despliegue en GKE, Nginx reverse proxy, CI/CD sin llaves estaticas y observabilidad en **GCP** para `quotes-api`.

- **URL Publica:** https://34.110.231.216.nip.io
- **Rama:** `feature/fabricio-neyra` | **Proyecto GCP:** `kambista-quotes-reto` (`us-central1-a`)

## 1. Documentacion
- **Arquitectura:** [`docs/arquitectura.md`](./docs/arquitectura.md)
- **Runbook operativo:** [`docs/runbook.md`](./docs/runbook.md)
- **Decisiones y trade-offs:** [`docs/decisiones.md`](./docs/decisiones.md)
- **Modulos Terraform:** [`terraform/README.md`](./terraform/README.md)
- **Evidencias visuales:** [`docs/evidencia/`](./docs/evidencia/)

## 2. Despliegue desde Cero
1. **Bucket de estado remoto:** `gcloud storage buckets create gs://kambista-quotes-reto-tfstate --location=us-central1 --uniform-bucket-level-access`
2. **Infraestructura Terraform:** `cd terraform && terraform init && terraform plan && terraform apply`
3. **Credenciales K8s, Secret desde Secret Manager y manifiestos:**
```bash
gcloud container clusters get-credentials kambista-gke-cluster --zone us-central1-a --project kambista-quotes-reto
kubectl apply -f ../k8s/00-namespace.yaml
MONGO_URI=$(gcloud secrets versions access latest --secret="quotes-mongo-uri")
MONGO_PASS=$(terraform output -raw mongo_password)
kubectl create secret generic mongo-secret -n quotes --from-literal=MONGO_INITDB_ROOT_USERNAME="quotes_admin" --from-literal=MONGO_INITDB_ROOT_PASSWORD="$MONGO_PASS" --from-literal=MONGO_URI="$MONGO_URI" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f ../k8s/
```
4. **CI/CD:** Cada `push` autentica por OIDC, sube la imagen (`sha-<commit>` y `latest`) a Artifact Registry, aplica `k8s/` en GKE y ejecuta un smoke test HTTPS.

## 3. Observabilidad, Bonus y Limpieza
- **Observabilidad:** Cloud Logging (`namespace="quotes"`), dashboard `Kambista - quotes-api GKE Overview` y alerta `quotes-api - Alerta de Reinicio de Contenedores (CrashLoop)`.
- **Bonus:** Prueba `k6/load-test.js` con autoescalado HPA (2 a 6 replicas), rate limit en Nginx (`20r/s`), estado remoto en GCS y smoke test en CI/CD.
- **Destruccion limpia:** `kubectl delete namespace quotes && cd terraform && terraform destroy -auto-approve`
