variable "project_id" {
  type = string
}

variable "github_repository_id" {
  description = "ID numérico del repo: gh api repos/OWNER/REPO --jq .id"
  type        = string
}

variable "github_owner_id" {
  description = "ID numérico del owner: gh api repos/OWNER/REPO --jq .owner.id"
  type        = string
}

variable "pool_id" {
  type    = string
  default = "github"
}

variable "deployer_account_id" {
  type    = string
  default = "github-deployer"
}

variable "deployer_project_roles" {
  type    = list(string)
  default = ["roles/container.developer"]
}
