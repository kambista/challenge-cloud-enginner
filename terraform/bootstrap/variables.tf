variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "state_bucket_name" {
  description = "Por defecto <project_id>-tfstate."
  type        = string
  default     = null
}

variable "state_bucket_force_destroy" {
  description = "Solo para el destroy final."
  type        = bool
  default     = false
}

variable "labels" {
  type = map(string)
  default = {
    project    = "quotes-api"
    managed-by = "terraform"
    env        = "challenge"
  }
}

variable "apis" {
  type = set(string)
  default = [
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
}
