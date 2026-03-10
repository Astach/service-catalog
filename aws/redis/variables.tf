# -----------------------------------------------------------------------------
# Redis (ElastiCache) - Variables
# Converted from Qovery engine Jinja2 templates to raw Terraform
#
# Uses aws_elasticache_replication_group (modern path with TLS + auth).
# The legacy aws_elasticache_cluster path (Redis 5.0) is intentionally dropped.
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
  description = "Explicit list of subnet IDs for the ElastiCache subnet group. If empty, derived from EKS cluster."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Explicit list of security group IDs. If empty, a new SG is created allowing traffic from the EKS cluster."
  type        = list(string)
  default     = []
}

variable "elasticache_subnet_group_name" {
  description = "Existing ElastiCache subnet group name. If empty, one is created from the EKS subnets."
  type        = string
  default     = ""
}

# =============================================================================
# Instance Configuration
# =============================================================================

variable "elasticache_identifier" {
  description = "ElastiCache replication group identifier (max 40 chars)"
  type        = string
}

variable "elasticache_version" {
  description = "Redis engine version (e.g. 7.0, 6.2)"
  type        = string
  default     = "7.0"
}

variable "parameter_group_name" {
  description = "ElastiCache parameter group name (e.g. default.redis7, default.redis6.x)"
  type        = string
  default     = "default.redis7"
}

variable "node_type" {
  description = "ElastiCache node type (e.g. cache.t4g.micro, cache.r6g.large)"
  type        = string
  default     = "cache.t4g.micro"
}

variable "port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (nodes) in the replication group"
  type        = number
  default     = 1
}

variable "encrypt_disk" {
  description = "Enable at-rest encryption"
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "Enable in-transit encryption (TLS)"
  type        = bool
  default     = true
}

# =============================================================================
# Authentication
# =============================================================================

variable "auth_token" {
  description = "Auth token (password) for Redis. Required when transit_encryption_enabled is true."
  type        = string
  sensitive   = true
}

# =============================================================================
# Snapshot Restore
# =============================================================================

variable "snapshot_identifier" {
  description = "Snapshot name to restore from. Leave empty for a fresh cluster."
  type        = string
  default     = ""
}

# =============================================================================
# Maintenance
# =============================================================================

variable "apply_changes_now" {
  description = "Apply changes immediately instead of during the maintenance window"
  type        = bool
  default     = false
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window (UTC)"
  type        = string
  default     = "Tue:02:00-Tue:04:00"
}

# =============================================================================
# Backup
# =============================================================================

variable "snapshot_retention_limit" {
  description = "Number of days to retain automatic snapshots (0 to disable)"
  type        = number
  default     = 14
}

variable "snapshot_window" {
  description = "Daily snapshot window (UTC)"
  type        = string
  default     = "00:00-01:00"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying the replication group"
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
