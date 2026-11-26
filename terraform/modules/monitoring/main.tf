locals {
  lb_requests = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" AND resource.type=\"https_lb_rule\""
  containers  = "resource.type=\"k8s_container\" AND resource.label.namespace_name=\"${var.namespace}\""
}

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "${var.name} on-call"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_uptime_check_config" "health" {
  project      = var.project_id
  display_name = "${var.name} /health"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/health"
    port         = 443
    use_ssl      = true
    validate_ssl = true
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.host
    }
  }
}

resource "google_monitoring_alert_policy" "uptime" {
  project               = var.project_id
  display_name          = "${var.name} - /health no responde"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email.id]

  conditions {
    display_name = "Uptime check fallando"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.health.uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "120s"
      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.*"]
      }
    }
  }

  documentation {
    content   = <<-EOT
      El uptime check no recibe 200 en /health.

      - `kubectl get pods -n ${var.namespace}`
      - `kubectl describe ingress quotes -n ${var.namespace}` (los backends deben estar HEALTHY)
      - `kubectl logs -n ${var.namespace} -l app=quotes-api --tail=100`
    EOT
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "error_rate" {
  project               = var.project_id
  display_name          = "${var.name} - 5xx > ${var.error_rate_threshold * 100}%"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email.id]

  conditions {
    display_name = "Ratio 5xx en el LB"
    condition_threshold {
      filter             = "${local.lb_requests} AND metric.label.response_code_class=500"
      denominator_filter = local.lb_requests
      comparison         = "COMPARISON_GT"
      threshold_value    = var.error_rate_threshold
      duration           = "300s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      denominator_aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  documentation {
    content   = <<-EOT
      Más del ${var.error_rate_threshold * 100}% de las respuestas del LB son 5xx.

      - `kubectl get pods -n ${var.namespace}`
      - `kubectl logs -n ${var.namespace} -l app=quotes-nginx --tail=200 | grep '"status":5'`
      - `kubectl exec -n ${var.namespace} mongodb-0 -c mongodb -- mongosh --quiet --eval "db.runCommand({ping:1})"`
    EOT
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "restarts" {
  project               = var.project_id
  display_name          = "${var.name} - reinicios de contenedores"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email.id]

  conditions {
    display_name = "Más de ${var.restart_threshold} reinicios en 10 min"
    condition_threshold {
      filter          = "metric.type=\"kubernetes.io/container/restart_count\" AND ${local.containers}"
      comparison      = "COMPARISON_GT"
      threshold_value = var.restart_threshold
      duration        = "0s"
      aggregations {
        alignment_period     = "600s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.pod_name"]
      }
    }
  }

  documentation {
    content   = <<-EOT
      Posible CrashLoopBackOff.

      - `kubectl get pods -n ${var.namespace}`
      - `kubectl logs <pod> -n ${var.namespace} --previous`
      - `kubectl describe pod <pod> -n ${var.namespace}`
    EOT
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_dashboard" "this" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "${var.name} overview"
    gridLayout = {
      columns = 2
      widgets = [
        {
          title = "Requests/s por clase de respuesta (LB)"
          xyChart = {
            dataSets = [{
              plotType = "STACKED_AREA"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = local.lb_requests
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields      = ["metric.label.response_code_class"]
                  }
                }
              }
            }]
          }
        },
        {
          title = "Latencia p95 (LB, ms)"
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"loadbalancing.googleapis.com/https/total_latencies\" AND resource.type=\"https_lb_rule\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_DELTA"
                    crossSeriesReducer = "REDUCE_PERCENTILE_95"
                  }
                }
              }
            }]
          }
        },
        {
          title = "CPU por contenedor (cores)"
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"kubernetes.io/container/cpu/core_usage_time\" AND ${local.containers}"
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields      = ["resource.label.container_name"]
                  }
                }
              }
            }]
          }
        },
        {
          title = "Memoria por contenedor"
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"kubernetes.io/container/memory/used_bytes\" AND metric.label.memory_type=\"non-evictable\" AND ${local.containers}"
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_MEAN"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields      = ["resource.label.container_name"]
                  }
                }
              }
            }]
          }
        },
        {
          title = "Pods de quotes-api"
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"kubernetes.io/container/uptime\" AND ${local.containers} AND resource.label.container_name=\"quotes-api\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_MEAN"
                    crossSeriesReducer = "REDUCE_COUNT"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Reinicios de contenedores"
          xyChart = {
            dataSets = [{
              plotType = "STACKED_BAR"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"kubernetes.io/container/restart_count\" AND ${local.containers}"
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_DELTA"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields      = ["resource.label.container_name"]
                  }
                }
              }
            }]
          }
        }
      ]
    }
  })
}
