# -----------------------------------------------------------------------------
# Prometheus + Grafana via Helm
#
# Uses the Terraform Helm provider (helm_release), so the same plan/approve
# workflow applies. terraform plan shows helm_release changes.
# -----------------------------------------------------------------------------

resource "helm_release" "prometheus" {
  name             = "prometheus"
  namespace        = var.kubernetes_namespace
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "58.2.1"
  timeout          = 600

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "${var.retention_days}d"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "${var.storage_size_gb}Gi"
  }

  set {
    name  = "grafana.enabled"
    value = tostring(var.grafana_enabled)
  }

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
}
