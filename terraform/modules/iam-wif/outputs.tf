output "provider_name" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_email" {
  value = google_service_account.deployer.email
}

output "deployer_member" {
  value = google_service_account.deployer.member
}
