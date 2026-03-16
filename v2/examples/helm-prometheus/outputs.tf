output "prometheus_url" {
  description = "Prometheus server internal URL"
  value       = "http://prometheus-kube-prometheus-prometheus.${var.kubernetes_namespace}.svc.cluster.local:9090"
}

output "grafana_url" {
  description = "Grafana internal URL (empty if Grafana disabled)"
  value       = var.grafana_enabled ? "http://prometheus-grafana.${var.kubernetes_namespace}.svc.cluster.local:80" : ""
}
