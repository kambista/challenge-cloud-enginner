output "cluster_name" {
  value = module.gke.name
}

output "cluster_location" {
  value = module.gke.location
}

output "get_credentials" {
  value = "gcloud container clusters get-credentials ${module.gke.name} --location ${module.gke.location} --project ${var.project_id} --dns-endpoint"
}

output "artifact_registry_url" {
  value = module.artifact_registry.repository_url
}

output "wif_provider" {
  value = module.iam_wif.provider_name
}

output "deployer_service_account" {
  value = module.iam_wif.deployer_email
}

output "ingress_ip_name" {
  value = module.edge.ip_name
}

output "ingress_ip" {
  value = module.edge.ip_address
}

output "hostname" {
  value = module.edge.hostname
}

output "security_policy_name" {
  value = module.edge.security_policy_name
}

output "ssl_policy_name" {
  value = module.edge.ssl_policy_name
}

output "backup_bucket" {
  value = module.backup.bucket_name
}

output "secret_ids" {
  value = module.secrets.secret_ids
}
