# 1. Habilitar APIs requeridas de GCP
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "time_sleep" "wait_apis" {
  depends_on      = [google_project_service.apis]
  create_duration = "30s"
}

# 2. Artifact Registry para imágenes Docker
resource "google_artifact_registry_repository" "quotes_repo" {
  depends_on    = [time_sleep.wait_apis]
  location      = var.region
  repository_id = "quotes-api"
  description   = "Repositorio Docker para quotes-api"
  format        = "DOCKER"
}

# 3. Secret Manager para la URI de MongoDB (contraseña generada dinámicamente)
resource "random_password" "mongo_password" {
  length           = 20
  special          = false
}

resource "google_secret_manager_secret" "mongo_uri" {
  depends_on = [time_sleep.wait_apis]
  secret_id  = "quotes-mongo-uri"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "mongo_uri_val" {
  secret      = google_secret_manager_secret.mongo_uri.id
  secret_data = "mongodb://quotes_admin:${random_password.mongo_password.result}@mongodb.quotes.svc.cluster.local:27017/quotes?authSource=admin"
}

# 4. IP Estática Global para el HTTP(S) Load Balancer
resource "google_compute_global_address" "ingress_ip" {
  depends_on = [time_sleep.wait_apis]
  name       = "quotes-ingress-ip"
}

# 5. Módulos principales: Red, IAM/WIF y GKE
module "network" {
  source     = "./modules/network"
  depends_on = [time_sleep.wait_apis]
  project_id = var.project_id
  region     = var.region
}

module "iam_cicd" {
  source          = "./modules/iam_cicd"
  depends_on      = [time_sleep.wait_apis]
  project_id      = var.project_id
  github_repo     = var.github_repo
  mongo_secret_id = google_secret_manager_secret.mongo_uri.secret_id
}

module "gke" {
  source               = "./modules/gke"
  depends_on           = [module.network, module.iam_cicd]
  project_id           = var.project_id
  zone                 = var.zone
  vpc_name             = module.network.vpc_name
  subnet_name          = module.network.subnet_name
  node_service_account = module.iam_cicd.gke_nodes_sa_email
}

# 6. Observabilidad: Dashboard y Alerta en Cloud Monitoring
resource "google_monitoring_dashboard" "quotes_dashboard" {
  depends_on = [time_sleep.wait_apis]
  dashboard_json = jsonencode({
    displayName = "Kambista - quotes-api GKE Overview"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "GKE Container CPU Utilization"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"kubernetes.io/container/cpu/core_usage_time\" resource.type=\"k8s_container\" resource.label.\"namespace_name\"=\"quotes\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        },
        {
          title = "GKE Container Memory Used (Bytes)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"kubernetes.io/container/memory/used_bytes\" resource.type=\"k8s_container\" resource.label.\"namespace_name\"=\"quotes\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "GKE Container Restart Count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"kubernetes.io/container/restart_count\" resource.type=\"k8s_container\" resource.label.\"namespace_name\"=\"quotes\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_DELTA"
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

resource "google_monitoring_alert_policy" "pod_restart_alert" {
  depends_on   = [time_sleep.wait_apis]
  display_name = "quotes-api - Alerta de Reinicio de Contenedores (CrashLoop)"
  combiner     = "OR"

  conditions {
    display_name = "Container Restart Count > 0"
    condition_threshold {
      filter          = "metric.type=\"kubernetes.io/container/restart_count\" AND resource.type=\"k8s_container\" AND resource.label.\"namespace_name\"=\"quotes\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_DELTA"
      }
    }
  }
}
# Vinculación Workload Identity de quotes-api (se crea después del clúster GKE)
resource "google_service_account_iam_member" "quotes_app_wi_binding" {
  depends_on         = [module.gke]
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.iam_cicd.quotes_app_sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[quotes/quotes-api-ksa]"
}
