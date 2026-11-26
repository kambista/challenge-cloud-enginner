# terraform

Infraestructura de `quotes-api` en GCP. Dos stacks con state remoto en GCS:

- `bootstrap/` se aplica una vez por proyecto.
- `envs/prd/` es el entorno; usa los módulos de `modules/`.

## Uso

```bash
PROJECT_ID=proyect-kambista-challenge

gcloud storage buckets create gs://${PROJECT_ID}-tfstate \
  --project=$PROJECT_ID --location=us-central1 \
  --uniform-bucket-level-access --public-access-prevention

cd bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

cd ../envs/prd
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

El bucket se crea a mano porque el backend lo necesita antes del primer `init`; `bootstrap` lo importa y desde ahí lo gestiona Terraform.

En otro proyecto, además de los tfvars, hay que cambiar `bucket` en los dos `backend.tf`.

## Inputs (`envs/prd`)

| Nombre | Default | |
|---|---|---|
| `project_id` | — | |
| `github_repository_id` | — | ID del repo autorizado en WIF (`gh api repos/OWNER/REPO --jq .id`) |
| `github_owner_id` | — | ID del owner (`--jq .owner.id`) |
| `alert_email` | — | |
| `region` | `us-central1` | |
| `authorized_networks` | `[]` | acceso al endpoint IP del control plane |
| `enable_cloud_armor` | `false` | requiere cuota de `SECURITY_POLICIES` en el proyecto |
| `rate_limit_per_minute` | `300` | por IP, solo con Cloud Armor |
| `allowed_countries` | `[]` | ISO alpha-2 |
| `eso_chart_version` | `2.15.0` | |

## Outputs

| Nombre | |
|---|---|
| `get_credentials` | comando para `kubectl` vía DNS endpoint |
| `wif_provider`, `deployer_service_account` | variables de GitHub Actions |
| `ingress_ip`, `hostname` | va en `helm/nginx/values.yaml` |
| `artifact_registry_url` | |
| `backup_bucket` | |
| `secret_ids` | |

## Notas

- El primer `apply` puede fallar en `helm_release.external_secrets` si el clúster todavía no responde. Se resuelve con un segundo `apply`.
- `deletion_protection` está apagado en el clúster y el bucket de backups tiene `force_destroy`, para poder desmontar el reto completo. En producción usaría protecciones contra eliminaciones accidentales.
- Las contraseñas de Mongo se generan con `random_password` y quedan en el state.
- Para destruir, usar `scripts/destroy.sh`: un `terraform destroy` directo con el Ingress vivo deja NEGs que bloquean el borrado de la VPC.
