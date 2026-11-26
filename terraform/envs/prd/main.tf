data "google_project" "this" {
  project_id = var.project_id
}

locals {
  k8s_principal    = "principal://iam.googleapis.com/projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${module.gke.workload_pool}/subject"
  eso_principal    = "${local.k8s_principal}/ns/external-secrets/sa/external-secrets"
  backup_principal = "${local.k8s_principal}/ns/${var.namespace}/sa/mongodb-backup"
}

module "network" {
  source = "../../modules/network"

  project_id = var.project_id
  region     = var.region
  name       = var.name
}

module "gke" {
  source = "../../modules/gke"

  project_id          = var.project_id
  region              = var.region
  name                = var.name
  network_id          = module.network.network_id
  subnet_id           = module.network.subnet_id
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  authorized_networks = var.authorized_networks
  labels              = var.labels
}

module "iam_wif" {
  source = "../../modules/iam-wif"

  project_id           = var.project_id
  github_repository_id = var.github_repository_id
  github_owner_id      = var.github_owner_id
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id = var.project_id
  region     = var.region
  name       = var.name
  readers    = [module.gke.node_service_account_member]
  writers    = [module.iam_wif.deployer_member]
  labels     = var.labels
}

module "secrets" {
  source = "../../modules/secrets"

  project_id = var.project_id
  mongo_host = "mongodb.${var.namespace}.svc.cluster.local"
  accessors  = [local.eso_principal]
  labels     = var.labels

  depends_on = [module.gke]
}

module "edge" {
  source = "../../modules/edge"

  project_id             = var.project_id
  name                   = var.name
  enable_security_policy = var.enable_cloud_armor
  allowed_countries      = var.allowed_countries
  rate_limit_per_minute  = var.rate_limit_per_minute
}

module "backup" {
  source = "../../modules/backup"

  project_id  = var.project_id
  region      = var.region
  bucket_name = "${var.project_id}-mongo-backups"
  writers     = [local.backup_principal]
  labels      = var.labels

  depends_on = [module.gke]
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_id  = var.project_id
  name        = var.name
  namespace   = var.namespace
  host        = module.edge.hostname
  alert_email = var.alert_email
}
