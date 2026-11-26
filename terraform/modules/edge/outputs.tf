output "ip_name" {
  value = google_compute_global_address.ingress.name
}

output "ip_address" {
  value = google_compute_global_address.ingress.address
}

output "hostname" {
  value = "${google_compute_global_address.ingress.address}.nip.io"
}

output "ssl_policy_name" {
  value = google_compute_ssl_policy.this.name
}

output "security_policy_name" {
  value = one(google_compute_security_policy.this[*].name)
}
