resource "random_password" "root" {
  length  = 32
  special = false
}

resource "random_password" "app" {
  length  = 32
  special = false
}

locals {
  values = {
    "mongo-root-password" = random_password.root.result
    "mongo-app-password"  = random_password.app.result
    "mongo-uri"           = "mongodb://${var.app_username}:${random_password.app.result}@${var.mongo_host}:27017/${var.database}?authSource=${var.database}"
  }

  accessor_bindings = {
    for pair in setproduct(keys(local.values), var.accessors) : "${pair[0]}|${pair[1]}" => {
      secret = pair[0]
      member = pair[1]
    }
  }
}

resource "google_secret_manager_secret" "this" {
  for_each = local.values

  project   = var.project_id
  secret_id = each.key

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "this" {
  for_each = local.values

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = each.value
}

resource "google_secret_manager_secret_iam_member" "accessors" {
  for_each = local.accessor_bindings

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
