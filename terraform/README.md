# Infraestructura como Codigo (Terraform) - quotes-api

Definicion modular de la infraestructura en GCP para `quotes-api`.

## Estructura de modulos
- `backend.tf`: Estado remoto en GCS (`kambista-quotes-reto-tfstate`).
- `main.tf` / `variables.tf` / `outputs.tf`: APIs, Artifact Registry, Secret Manager, IP global y Monitoring.
- `modules/network`: VPC dedicada, subred con rangos secundarios, Cloud Router y Cloud NAT.
- `modules/gke`: Cluster GKE Standard Zonal privado (`us-central1-a`) con Workload Identity.
- `modules/iam_cicd`: Service Accounts y Workload Identity Federation (GitHub OIDC).

## Ejecucion
```bash
cd terraform
terraform init && terraform plan && terraform apply
# Para destruir toda la infraestructura:
terraform destroy
```
