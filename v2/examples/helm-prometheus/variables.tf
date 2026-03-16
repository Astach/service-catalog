# -----------------------------------------------------------------------------
# Qovery Variables (auto-filled by q-core)
# -----------------------------------------------------------------------------

variable "kubernetes_namespace" {
  description = "Kubernetes namespace for the Helm release"
  type        = string
  default     = "monitoring"
}

# -----------------------------------------------------------------------------
# User Variables
# -----------------------------------------------------------------------------

variable "retention_days" {
  description = "Prometheus data retention in days"
  type        = number
  default     = 15
}

variable "storage_size_gb" {
  description = "Persistent volume size in GB"
  type        = number
  default     = 50
}

variable "grafana_enabled" {
  description = "Deploy Grafana alongside Prometheus"
  type        = bool
  default     = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "admin"
  sensitive   = true
}
