variable "project_id" {
  type = string
}

variable "github_repo" {
  type        = string
  description = "Repositorio en formato owner/repo"
}

variable "mongo_secret_id" {
  type = string
}