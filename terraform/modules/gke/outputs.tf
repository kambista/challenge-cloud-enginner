output "name" {
  value = google_container_cluster.this.name
}

output "location" {
  value = google_container_cluster.this.location
}

output "dns_endpoint" {
  value = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "workload_pool" {
  value = "${var.project_id}.svc.id.goog"
}

output "node_service_account_member" {
  value = google_service_account.nodes.member
}
