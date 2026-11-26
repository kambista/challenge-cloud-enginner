output "dashboard_id" {
  value = google_monitoring_dashboard.this.id
}

output "uptime_check_id" {
  value = google_monitoring_uptime_check_config.health.uptime_check_id
}
