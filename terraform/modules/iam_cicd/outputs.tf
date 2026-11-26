output "gke_nodes_sa_email" {
  value = google_service_account.gke_nodes.email
}

output "quotes_app_sa_email" {
  value = google_service_account.quotes_app.email
}

output "github_actions_sa_email" {
  value = google_service_account.github_actions.email
}

output "workload_identity_provider_name" {
  value = google_iam_workload_identity_pool_provider.github_provider.name
}