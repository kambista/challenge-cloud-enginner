# quotes-api en GCP

`quotes-api` corre en GKE (Google Kubernetes Engine) Autopilot junto a MongoDB, detrás de un HTTPS Load Balancer con Nginx como reverse proxy. La infraestructura está en Terraform y GitHub Actions despliega sin llaves, mediante Workload Identity Federation.

- URL: `https://136.82.17.30.nip.io`
- [Arquitectura](docs/arquitectura.md)
- [Runbook](docs/runbook.md)
- [Decisiones y trade-offs](docs/decisiones.md)
- [Evidencia](docs/evidencia/README.md)

## Estructura

```
.github/workflows/   deploy.yml y ci.yml
app/                 quotes-api del reto, sin cambios
terraform/
  bootstrap/         APIs y bucket del state
  envs/prd/
  modules/
helm/
  external-secrets/  ClusterSecretStore, lo instala Terraform
  mongodb/           incluye el backup diario a Cloud Storage
  quotes-api/
  nginx/             incluye el Ingress y el certificado
scripts/             restore de Mongo, rotación de la credencial y destroy
load-test/
docs/
```

## Requisitos

Un proyecto GCP con billing donde tengas rol de Owner, y `gcloud`, `terraform >= 1.6`, `kubectl` con `gke-gcloud-auth-plugin`, `helm 3` y `docker`, autenticados con `gcloud auth login` y `gcloud auth application-default login`.

## Desplegar desde cero

### 1. Bootstrap

Antes de cualquier `terraform init` debe existir el bucket de GCS que guarda el state, ya que el backend lo necesita para inicializarse. Como Terraform no puede crear el bucket donde va a guardar su propio state, este paso se hace con `gcloud` y solo al preparar el proyecto; los despliegues siguientes reutilizan el mismo bucket:

```bash
PROJECT_ID=proyect-kambista-challenge

gcloud storage buckets create gs://${PROJECT_ID}-tfstate \
  --project=$PROJECT_ID --location=us-central1 \
  --uniform-bucket-level-access --public-access-prevention
```

Luego el bootstrap importa ese bucket al state, le aplica versionado y reglas de lifecycle, y habilita las APIs del proyecto:

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

Para desplegar en un proyecto distinto, basta con reemplazar el valor de `project_id` en los `terraform.tfvars` y el nombre del `bucket` en los archivos `backend.tf` de `bootstrap` y `envs/prd`, de modo que ambos apunten al bucket creado en el paso anterior.

### 2. Infraestructura

```bash
cd ../envs/prd
cp terraform.tfvars.example terraform.tfvars   # IDs del repo, alert_email, authorized_networks
terraform init && terraform apply
```

El `apply` tarda alrededor de 15 minutos, la mayor parte en la creación del clúster de GKE. Al final, Terraform instala External Secrets con Helm. Si el clúster todavía no acepta conexiones, ese paso puede fallar aunque el resto de la infraestructura ya esté creada. En ese caso basta con volver a ejecutar `terraform apply`: solo completa lo que quedó pendiente.

### 3. Host del Ingress

```bash
IP=$(terraform output -raw ingress_ip)
sed -i -E "s/^(  host: ).*/\1${IP}.nip.io/" ../../../helm/nginx/values.yaml
```

### 4. GitHub Actions

El pipeline no usa secretos, solo estas variables del repo:

| Variable | Valor |
|---|---|
| `GCP_PROJECT_ID` | `proyect-kambista-challenge` |
| `GCP_REGION` | `us-central1` |
| `GKE_CLUSTER` | `terraform output -raw cluster_name` |
| `WIF_PROVIDER` | `terraform output -raw wif_provider` |
| `DEPLOYER_SA` | `terraform output -raw deployer_service_account` |

Con las variables configuradas, se hace commit y push del `values.yaml` de Nginx con el host del paso anterior. Los push solo despliegan los charts que cambiaron, así que el primer despliegue se lanza manualmente desde *Actions → deploy → Run workflow*: la ejecución manual construye la imagen e instala Mongo, la API y Nginx en ese orden.

### 5. Verificar

```bash
$(terraform -chdir=terraform/envs/prd output -raw get_credentials)
kubectl get pods,svc,ingress,hpa -n quotes
kubectl describe managedcertificate quotes -n quotes   # Active en 15-60 min

curl https://${IP}.nip.io/health
curl -X POST https://${IP}.nip.io/quotes -H 'content-type: application/json' \
  -d '{"pair":"USD/PEN","buy":3.70,"sell":3.75}'
curl https://${IP}.nip.io/quotes
```

## Destruir

```bash
scripts/destroy.sh
```

El script desinstala primero los charts y espera a que GKE libere el load balancer; recién entonces borra el volumen de Mongo, corre `terraform destroy` en ambas fases y elimina el bucket del state. Ese orden evita que los NEGs y forwarding rules creados por GKE bloqueen el borrado de la VPC. Con `KEEP_BOOTSTRAP=1` se conservan las APIs y el bucket.

## Prueba de carga

`load-test/k6-quotes.js` simula usuarios que consultan y publican cotizaciones, con un 80% de lecturas y un 20% de escrituras. La carga sube de forma gradual hasta 80 usuarios concurrentes, se mantiene así unos minutos y luego baja; en total dura 10 minutos. La prueba se considera aprobada si menos del 1% de las requests falla y el p95 queda por debajo de 500 ms en `GET /quotes` y de 800 ms en `POST /quotes`.

Como k6 envía todo el tráfico desde una sola IP, el rate limit de Nginx lo frenaría a los pocos segundos y la prueba mediría los 429 en lugar del comportamiento de la API. Por eso se desactiva antes de empezar:

```bash
helm upgrade nginx helm/nginx -n quotes --reuse-values --set rateLimit.enabled=false --wait
```

El script recibe la URL del servicio en la variable `BASE_URL` y se detiene si no está definida. Se toma de la IP del Ingress que entrega Terraform:

```bash
BASE_URL=https://$(terraform -chdir=terraform/envs/prd output -raw ingress_ip).nip.io
```

Con el límite apagado se lanza k6, y en otra terminal se puede seguir cómo el HPA agrega réplicas a medida que sube la CPU:

```bash
docker run --rm -i grafana/k6 run -e BASE_URL=$BASE_URL - < load-test/k6-quotes.js
kubectl get hpa -n quotes -w
```

Al terminar, se vuelve a activar el rate limit para que el servicio quede protegido como antes:

```bash
helm upgrade nginx helm/nginx -n quotes --reuse-values --set rateLimit.enabled=true --wait
```

Si Cloud Armor está activo, su propia regla de rate limit también bloquearía la prueba, así que hay que subir `rate_limit_per_minute` en Terraform durante la prueba y restaurarlo después.

## Observabilidad

Todo lo de observabilidad está definido en el módulo `terraform/modules/monitoring`, así que se crea y se destruye junto con el resto del entorno.

**Logs.** Nginx escribe cada request en JSON, con status, latencia del upstream e IP real del cliente, lo que permite filtrarlos directamente en Logs Explorer sin parsear texto. La API y Mongo envían sus logs a Cloud Logging como cualquier contenedor de GKE, y el Load Balancer registra todas las requests que recibe, incluidas las que nunca llegan al clúster.

**Dashboard.** `quotes overview` muestra en una sola vista lo que hace falta para entender el estado del servicio:
- requests por segundo según la clase de respuesta, para ver de un vistazo si aparecen 4xx o 5xx;
- latencia p95 medida en el Load Balancer, que es la que perciben los clientes;
- CPU y memoria por contenedor, para detectar si la presión está en la API, en Nginx o en Mongo;
- cantidad de pods de la API, que refleja lo que está haciendo el HPA;
- reinicios de contenedores.

**Alertas.** Se envían al correo definido en `alert_email`. Cada notificación trae los comandos iniciales de diagnóstico, de modo que cualquier persona del equipo que la reciba puede empezar a investigar sin conocer el proyecto de antemano:

| Alerta | Cuándo se dispara |
|---|---|
| `/health` no responde | El uptime check, que consulta `/health` por HTTPS cada minuto desde varias regiones, falla en más de una región durante 2 minutos. |
| 5xx sobre 5% | Más del 5% de las respuestas del Load Balancer son 5xx durante 5 minutos seguidos. |
| Reinicios de contenedores | Un pod se reinicia más de 3 veces en 10 minutos, la señal típica de un `CrashLoopBackOff`. |

El umbral de 5xx está por encima del objetivo de 1% a propósito: con poco tráfico, un par de errores aislados ya supera el 1% y la alerta perdería credibilidad.

**Qué agregaría con tráfico real:**
- Alertas por SLO y burn rate sobre latencia y errores por endpoint. En vez de avisar por cada pico, avisan cuando el presupuesto de error se está consumiendo más rápido de lo sostenible.
- Saturación de Mongo: conexiones, uso de cache, queries lentas y espacio en disco. Es la pieza con estado y la que más tarda en recuperarse.
- Edad del último backup exitoso, porque un backup que falla en silencio se descubre el día que hace falta.
- Expiración del certificado y bloqueos de Cloud Armor, para distinguir un ataque de un falso positivo que deja afuera a clientes reales.
- Cotizaciones creadas por minuto y antigüedad de la última cotización por par. Si un proveedor deja de publicar, el servicio sigue respondiendo en verde, pero muestra precios viejos, que en una casa de cambio es el peor escenario.
