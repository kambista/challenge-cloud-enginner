variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "name" {
  type    = string
  default = "quotes"
}

variable "namespace" {
  type    = string
  default = "quotes"
}

variable "github_repository_id" {
  description = "ID numérico del repo autorizado en WIF."
  type        = string
}

variable "github_owner_id" {
  description = "ID numérico del owner del repo."
  type        = string
}

variable "alert_email" {
  type = string
}

variable "authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "allowed_countries" {
  type    = list(string)
  default = []
}

variable "enable_cloud_armor" {
  description = "Requiere cuota de SECURITY_POLICIES en el proyecto."
  type        = bool
  default     = false
}

variable "rate_limit_per_minute" {
  description = "Requests por minuto por IP en Cloud Armor. Subirlo solo durante pruebas de carga."
  type        = number
  default     = 300
}

variable "eso_chart_version" {
  type    = string
  default = "2.15.0"
}

variable "labels" {
  type = map(string)
  default = {
    project    = "quotes-api"
    managed-by = "terraform"
    env        = "prd"
  }
}
