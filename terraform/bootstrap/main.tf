locals {
  state_bucket_name = coalesce(var.state_bucket_name, "${var.project_id}-tfstate")
}

resource "google_project_service" "apis" {
  for_each = var.apis

  project = var.project_id
  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}

import {
  to = google_storage_bucket.tfstate
  id = local.state_bucket_name
}

resource "google_storage_bucket" "tfstate" {
  project  = var.project_id
  name     = local.state_bucket_name
  location = var.region

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.state_bucket_force_destroy

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
      with_state                 = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels

  depends_on = [google_project_service.apis]
}
