# -----------------------------------------------------------------------------
# PostgreSQL RDS - Main Resources
# -----------------------------------------------------------------------------

# =============================================================================
# Data Sources - Network & IAM Discovery
# =============================================================================

data "aws_vpc" "selected" {
  count = var.vpc_id == "" ? 1 : 0

  filter {
    name   = "tag:ClusterId"
    values = [var.kubernetes_cluster_id]
  }
}

data "aws_security_group" "selected" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  filter {
    name   = "tag:Name"
    values = ["qovery-${var.kubernetes_cluster_id}-sg-workers", "qovery-eks-workers"]
  }

  filter {
    name   = "tag:kubernetes.io/cluster/qovery-${var.kubernetes_cluster_id}"
    values = ["owned"]
  }
}

data "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.monitoring_role_arn == "" && var.monitoring_interval > 0 ? 1 : 0
  name  = "qovery-rds-enhanced-monitoring-${var.kubernetes_cluster_id}"
}

# =============================================================================
# Locals
# =============================================================================

locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.selected[0].id

  security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : data.aws_security_group.selected[*].id

  db_subnet_group_name = var.db_subnet_group_name != "" ? var.db_subnet_group_name : local.vpc_id

  monitoring_role_arn = var.monitoring_role_arn != "" ? var.monitoring_role_arn : (
    var.monitoring_interval > 0 ? data.aws_iam_role.rds_enhanced_monitoring[0].arn : null
  )

  final_snap_timestamp  = replace(timestamp(), "/[- TZ:]/", "")
  final_snapshot_name   = "${var.final_snapshot_name}-${local.final_snap_timestamp}"

  is_snapshot_restore = var.snapshot_identifier != ""

  base_tags = merge(
    {
      "ManagedBy"   = "terraform"
      "Service"     = "postgresql"
      "Environment" = var.environment
      "Project"     = var.project
      "Identifier"  = var.postgresql_identifier
      "CreatedAt"   = time_static.on_db_create.rfc3339
    },
    var.tags,
  )
}

# =============================================================================
# Timestamp for tagging
# =============================================================================

resource "time_static" "on_db_create" {}

# =============================================================================
# RDS PostgreSQL Instance
# =============================================================================

resource "aws_db_instance" "postgresql" {
  identifier        = var.postgresql_identifier
  tags              = local.base_tags
  instance_class    = var.instance_class
  port              = var.port
  password          = var.password
  storage_encrypted = var.encrypt_disk

  # ---------------------------------------------------------------------------
  # Snapshot restore vs. fresh creation
  # When restoring from a snapshot, engine/storage/username/db_name are inherited
  # ---------------------------------------------------------------------------
  snapshot_identifier = local.is_snapshot_restore ? var.snapshot_identifier : null
  allocated_storage   = local.is_snapshot_restore ? null : var.disk_size
  db_name             = local.is_snapshot_restore ? null : var.database_name
  storage_type        = local.is_snapshot_restore ? null : var.storage_type
  username            = local.is_snapshot_restore ? null : var.username
  engine_version      = local.is_snapshot_restore ? null : var.postgresql_version
  engine              = local.is_snapshot_restore ? null : "postgres"
  ca_cert_identifier  = local.is_snapshot_restore ? null : var.ca_cert_identifier
  iops                = local.is_snapshot_restore ? null : (var.enable_disk_iops ? var.disk_iops : null)

  # ---------------------------------------------------------------------------
  # Network
  # ---------------------------------------------------------------------------
  db_subnet_group_name   = local.db_subnet_group_name
  vpc_security_group_ids = local.security_group_ids
  publicly_accessible    = var.publicly_accessible
  multi_az               = var.multi_az

  # ---------------------------------------------------------------------------
  # Maintenance & Upgrades
  # ---------------------------------------------------------------------------
  apply_immediately           = var.apply_changes_now
  allow_major_version_upgrade = var.allow_major_version_upgrade
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  maintenance_window          = var.preferred_maintenance_window

  # ---------------------------------------------------------------------------
  # Monitoring
  # ---------------------------------------------------------------------------
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention : null
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = local.monitoring_role_arn

  # ---------------------------------------------------------------------------
  # Backup
  # ---------------------------------------------------------------------------
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.preferred_backup_window
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_name
  copy_tags_to_snapshot     = var.copy_tags_to_snapshot
  delete_automated_backups  = var.delete_automated_backups

  # ---------------------------------------------------------------------------
  # Timeouts
  # ---------------------------------------------------------------------------
  timeouts {
    create = "60m"
    update = "120m"
    delete = "60m"
  }

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------
  lifecycle {
    ignore_changes = [
      final_snapshot_identifier,
      parameter_group_name,
    ]
  }
}
