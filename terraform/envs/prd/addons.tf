resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.eso_chart_version
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    installCRDs = true
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
    }
    webhook = {
      resources = { requests = { cpu = "50m", memory = "64Mi" } }
    }
    certController = {
      resources = { requests = { cpu = "50m", memory = "64Mi" } }
    }
  })]

  depends_on = [module.gke]
}

resource "helm_release" "external_secrets_config" {
  name      = "external-secrets-config"
  chart     = "${path.root}/../../../helm/external-secrets"
  namespace = "external-secrets"
  wait      = true

  values = [yamlencode({
    projectId  = var.project_id
    namespaces = [var.namespace]
  })]

  depends_on = [helm_release.external_secrets, module.secrets]
}
