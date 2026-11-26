variable "project_id" {
  type        = string
  default     = "kambista-quotes-reto"
  description = "ID del proyecto en GCP"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Región de GCP"
}

variable "zone" {
  type        = string
  default     = "us-central1-a"
  description = "Zona para el clúster GKE Zonal"
}

variable "github_repo" {
  type        = string
  default     = "Fabri-99/challenge-cloud-enginner"
  description = "Repositorio de GitHub autorizado en Workload Identity Federation"
}