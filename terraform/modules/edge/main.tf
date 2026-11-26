resource "google_compute_global_address" "ingress" {
  project      = var.project_id
  name         = "${var.name}-ingress-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "google_compute_ssl_policy" "this" {
  project         = var.project_id
  name            = "${var.name}-ssl-policy"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

resource "google_compute_security_policy" "this" {
  count = var.enable_security_policy ? 1 : 0

  project = var.project_id
  name    = "${var.name}-armor"

  rule {
    action      = "deny(403)"
    priority    = 1000
    description = "SQLi"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1100
    description = "XSS"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  dynamic "rule" {
    for_each = length(var.allowed_countries) > 0 ? [1] : []
    content {
      action      = "deny(403)"
      priority    = 1500
      description = "Geo"
      match {
        expr {
          expression = "!(${join(" || ", [for c in var.allowed_countries : "origin.region_code == '${c}'"])})"
        }
      }
    }
  }

  rule {
    action      = "throttle"
    priority    = 2000
    description = "Rate limit por IP"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.rate_limit_per_minute
        interval_sec = 60
      }
    }
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
