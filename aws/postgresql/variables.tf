# -----------------------------------------------------------------------------
# PostgreSQL RDS - Variables
#
# qoveryVariables (auto-filled by q-core based on qsm.yml) are in the first
# section. User variables are below.
# -----------------------------------------------------------------------------

# =============================================================================
# Qovery Variables (auto-filled from cluster/environment context)
# =============================================================================

variable "qovery_cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "region" {
  description = "AWS region (overridable)"
  type        = string
}

variable "qovery_environment_id" {
  description = "Qovery environment ID"
  type        = string
  default     = ""
}

variable "qovery_project_id" {
  description = "Qovery project ID"
  type        = string
  default     = ""
}

# =============================================================================
# Network Overrides (optional -- derived from EKS cluster by default)
# =============================================================================

variable "vpc_id" {
  description = "Explicit VPC ID. If empty, derived from the EKS cluster."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Explicit list of subnet IDs for the DB subnet group. If empty, derived from EKS cluster."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Explicit list of security group IDs. If empty, a new SG is created allowing traffic from the EKS cluster."
  type        = list(string)
  default     = []
}

variable "db_subnet_group_name" {
  description = "Existing DB subnet group name. If empty, one is created from the EKS subnets."
  type        = string
  default     = ""
}

# =============================================================================
# Instance Configuration
# =============================================================================

variable "postgresql_identifier" {
  description = "RDS instance identifier"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class (e.g. db.t3.micro, db.r6g.large)"
  type        = string
  default     = "db.t3.micro"
}

variable "postgresql_version" {
  description = "PostgreSQL engine version (e.g. 15, 15.3, 16.1)"
  type        = string
  default     = "16"
}

variable "port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "storage_type" {
  description = "Storage type: standard, gp2, gp3, io1, io2"
  type        = string
  default     = "gp3"
}

variable "disk_size" {
  description = "Allocated storage in GiB"
  type        = number
  default     = 20
}

variable "disk_iops" {
  description = "Provisioned IOPS. Only used when storage_type is io1/io2/gp3."
  type        = number
  default     = 3000
}

variable "enable_disk_iops" {
  description = "Whether to set the iops parameter on the RDS instance"
  type        = bool
  default     = false
}

variable "encrypt_disk" {
  description = "Enable storage encryption at rest"
  type        = bool
  default     = true
}

variable "ca_cert_identifier" {
  description = "RDS CA certificate identifier"
  type        = string
  default     = "rds-ca-rsa2048-g1"
}

# =============================================================================
# Authentication
# =============================================================================

variable "database_name" {
  description = "Name of the default database to create"
  type        = string
  default     = "postgres"
}

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
    error_message = "The parameter MasterUserPassword is not a valid password because it is shorter than 8 characters."
  }
}

# =============================================================================
# Snapshot Restore
# =============================================================================

variable "snapshot_identifier" {
  description = "Snapshot ID to restore from. Leave empty for a fresh instance."
  type        = string
  default     = ""
}

# =============================================================================
# High Availability & Network Access
# =============================================================================

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = true
}

variable "publicly_accessible" {
  description = "Whether the instance is publicly accessible"
  type        = bool
  default     = false
}

# =============================================================================
# Maintenance & Upgrades
# =============================================================================

variable "apply_changes_now" {
  description = "Apply changes immediately instead of during the maintenance window"
  type        = bool
  default     = false
}

variable "allow_major_version_upgrade" {
  description = "Allow major engine version upgrades"
  type        = bool
  default     = true
}

variable "auto_minor_version_upgrade" {
  description = "Automatically apply minor engine version upgrades"
  type        = bool
  default     = true
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window (UTC)"
  type        = string
  default     = "Tue:02:00-Tue:04:00"
}

# =============================================================================
# Monitoring
# =============================================================================

variable "performance_insights_enabled" {
  description = "Enable RDS Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention" {
  description = "Performance Insights data retention in days (7, 31, 62, ...731)"
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0, 1, 5, 10, 15, 30, 60). Set to 0 to disable."
  type        = number
  default     = 10
}

# =============================================================================
# Backup
# =============================================================================

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 14
}

variable "preferred_backup_window" {
  description = "Daily backup window (UTC)"
  type        = string
  default     = "00:00-01:00"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying the instance"
  type        = bool
  default     = false
}

variable "final_snapshot_name" {
  description = "Base name for the final snapshot (a timestamp is appended automatically)"
  type        = string
  default     = "final-snapshot"
}

variable "copy_tags_to_snapshot" {
  description = "Copy all tags to snapshots"
  type        = bool
  default     = true
}

variable "delete_automated_backups" {
  description = "Delete automated backups when the instance is deleted"
  type        = bool
  default     = false
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
