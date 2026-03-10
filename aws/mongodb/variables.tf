# -----------------------------------------------------------------------------
# MongoDB (DocumentDB) - Variables
# Converted from Qovery engine Jinja2 templates to raw Terraform
# -----------------------------------------------------------------------------

# =============================================================================
# Qovery Context
# =============================================================================

variable "qovery_cluster_name" {
  description = "EKS cluster name. Maps to Qovery built-in: QOVERY_KUBERNETES_CLUSTER_NAME"
  type        = string
}

variable "region" {
  description = "AWS region. Maps to Qovery built-in: QOVERY_CLOUD_PROVIDER_REGION"
  type        = string
}

variable "qovery_environment_id" {
  description = "Qovery environment ID. Maps to Qovery built-in: QOVERY_ENVIRONMENT_ID"
  type        = string
  default     = ""
}

variable "qovery_project_id" {
  description = "Qovery project ID. Maps to Qovery built-in: QOVERY_PROJECT_ID"
  type        = string
  default     = ""
}

# =============================================================================
# Network Overrides
# =============================================================================

variable "vpc_id" {
  description = "Explicit VPC ID. If empty, derived from the EKS cluster."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Explicit list of subnet IDs for the DocumentDB subnet group. If empty, derived from EKS cluster."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Explicit list of security group IDs. If empty, a new SG is created allowing traffic from the EKS cluster."
  type        = list(string)
  default     = []
}

variable "docdb_subnet_group_name" {
  description = "Existing DocumentDB subnet group name. If empty, one is created from the EKS subnets."
  type        = string
  default     = ""
}

# =============================================================================
# Cluster Configuration
# =============================================================================

variable "documentdb_identifier" {
  description = "DocumentDB cluster identifier"
  type        = string
}

variable "documentdb_version" {
  description = "DocumentDB engine version (e.g. 4.0, 5.0)"
  type        = string
  default     = "5.0"
}

variable "instance_class" {
  description = "DocumentDB instance class (e.g. db.r5.large, db.t3.medium)"
  type        = string
  default     = "db.t3.medium"
}

variable "instances_number" {
  description = "Number of instances in the DocumentDB cluster"
  type        = number
  default     = 1
}

variable "port" {
  description = "DocumentDB port"
  type        = number
  default     = 27017
}

variable "encrypt_disk" {
  description = "Enable storage encryption at rest"
  type        = bool
  default     = true
}

# =============================================================================
# Authentication
# =============================================================================

variable "username" {
  description = "Master username"
  type        = string
  default     = "qovery"
}

variable "password" {
  description = "Master password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.password) > 8
    error_message = "Password must be longer than 8 characters."
  }
}

# =============================================================================
# Snapshot Restore
# =============================================================================

variable "snapshot_identifier" {
  description = "Snapshot ID to restore from. Leave empty for a fresh cluster."
  type        = string
  default     = ""
}

# =============================================================================
# Maintenance & Upgrades
# =============================================================================

variable "apply_changes_now" {
  description = "Apply changes immediately instead of during the maintenance window"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Automatically apply minor engine version upgrades to instances"
  type        = bool
  default     = true
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window (UTC)"
  type        = string
  default     = "Tue:02:00-Tue:04:00"
}

# =============================================================================
# Backup
# =============================================================================

variable "backup_retention_period" {
  description = "Number of days to retain automated backups (1-35)"
  type        = number
  default     = 14
}

variable "preferred_backup_window" {
  description = "Daily backup window (UTC)"
  type        = string
  default     = "00:00-01:00"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying the cluster"
  type        = bool
  default     = false
}

variable "final_snapshot_name" {
  description = "Base name for the final snapshot (a timestamp is appended automatically)"
  type        = string
  default     = "final-snapshot"
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
