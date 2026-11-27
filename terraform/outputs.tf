output "ingress_public_ip" {
  value       = google_compute_global_address.ingress_ip.address
  description = "IP pública reservada para el Load Balancer"
}

output "nip_io_domain" {
  value       = "${google_compute_global_address.ingress_ip.address}.nip.io"
  description = "Dominio wildcard HTTPS para el Ingress"
}

output "artifact_registry_repo" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.quotes_repo.repository_id}"
  description = "URL del repositorio Docker en Artifact Registry"
}

output "workload_identity_provider" {
  value       = module.iam_cicd.workload_identity_provider_name
  description = "Provider ID para configurar GitHub Actions"
}

output "github_actions_sa" {
  value       = module.iam_cicd.github_actions_sa_email
  description = "Service Account de GitHub Actions"
}

output "mongo_password" {
  value       = random_password.mongo_password.result
  sensitive   = true
  description = "Contraseña generada para MongoDB"
}

output "gke_get_credentials_cmd" {
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --zone ${module.gke.cluster_location} --project ${var.project_id}"
  description = "Comando para conectar kubectl al clúster"
}