# -----------------------------------------------------------------------------
# PostgreSQL RDS - Main Resources
#
# Network discovery uses the EKS cluster data source (same pattern as Qovery's
# lifecycle-job-examples). VPC, subnets, and security groups are derived from
# the cluster automatically, but can be overridden via variables.
# -----------------------------------------------------------------------------

# =============================================================================
# Data Sources
# =============================================================================

data "aws_eks_cluster" "cluster" {
  name = var.qovery_cluster_name
}

# =============================================================================
# Locals
# =============================================================================

locals {
  # Network: derive from EKS cluster or use explicit overrides
  vpc_id             = var.vpc_id != "" ? var.vpc_id : data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
  subnet_ids         = length(var.subnet_ids) > 0 ? var.subnet_ids : tolist(data.aws_eks_cluster.cluster.vpc_config[0].subnet_ids)
  security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.rds[0].id]
  db_subnet_group    = var.db_subnet_group_name != "" ? var.db_subnet_group_name : aws_db_subnet_group.rds[0].name

  # Snapshot restore logic
  is_snapshot_restore = var.snapshot_identifier != ""

  # Final snapshot naming
  final_snap_timestamp = replace(timestamp(), "/[- TZ:]/", "")
  final_snapshot_name  = "${var.final_snapshot_name}-${local.final_snap_timestamp}"

  # Tags
  base_tags = merge(
    {
      "ManagedBy"     = "terraform"
      "Service"       = "postgresql"
      "Identifier"    = var.postgresql_identifier
      "ClusterName"   = var.qovery_cluster_name
      "Region"        = var.region
      "EnvironmentId" = var.qovery_environment_id
      "ProjectId"     = var.qovery_project_id
      "CreatedAt"     = time_static.on_db_create.rfc3339
    },
    var.tags,
  )
}

# =============================================================================
# Timestamp for tagging
# =============================================================================

resource "time_static" "on_db_create" {}

# =============================================================================
# Network Resources (created only when not using explicit overrides)
# =============================================================================

resource "aws_security_group" "rds" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name        = "${var.postgresql_identifier}-rds-sg"
  description = "Security group for RDS PostgreSQL ${var.postgresql_identifier}"
  vpc_id      = local.vpc_id
  tags        = merge(local.base_tags, { "Name" = "${var.postgresql_identifier}-rds-sg" })

  # Allow inbound PostgreSQL traffic from the EKS cluster security group
  ingress {
    description     = "PostgreSQL from EKS cluster"
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = [data.aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "rds" {
  count = var.db_subnet_group_name == "" ? 1 : 0

  name       = "${var.postgresql_identifier}-subnet-group"
  subnet_ids = local.subnet_ids
  tags       = merge(local.base_tags, { "Name" = "${var.postgresql_identifier}-subnet-group" })
}

# =============================================================================
# IAM Role for Enhanced Monitoring (created only when monitoring is enabled)
# =============================================================================

resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name = "${var.postgresql_identifier}-rds-monitoring"
  tags = local.base_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

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
  db_subnet_group_name   = local.db_subnet_group
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
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

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
