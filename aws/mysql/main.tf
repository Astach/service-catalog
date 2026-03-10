# -----------------------------------------------------------------------------
# MySQL RDS - Main Resources
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
  vpc_id             = var.vpc_id != "" ? var.vpc_id : data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
  subnet_ids         = length(var.subnet_ids) > 0 ? var.subnet_ids : tolist(data.aws_eks_cluster.cluster.vpc_config[0].subnet_ids)
  security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.rds[0].id]
  db_subnet_group    = var.db_subnet_group_name != "" ? var.db_subnet_group_name : aws_db_subnet_group.rds[0].name

  is_snapshot_restore  = var.snapshot_identifier != ""
  final_snap_timestamp = replace(timestamp(), "/[- TZ:]/", "")
  final_snapshot_name  = "${var.final_snapshot_name}-${local.final_snap_timestamp}"

  base_tags = merge(
    {
      "ManagedBy"     = "terraform"
      "Service"       = "mysql"
      "Identifier"    = var.mysql_identifier
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
# Network Resources
# =============================================================================

resource "aws_security_group" "rds" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name        = "${var.mysql_identifier}-rds-sg"
  description = "Security group for RDS MySQL ${var.mysql_identifier}"
  vpc_id      = local.vpc_id
  tags        = merge(local.base_tags, { "Name" = "${var.mysql_identifier}-rds-sg" })

  ingress {
    description     = "MySQL from EKS cluster"
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

  name       = "${var.mysql_identifier}-subnet-group"
  subnet_ids = local.subnet_ids
  tags       = merge(local.base_tags, { "Name" = "${var.mysql_identifier}-subnet-group" })
}

# =============================================================================
# IAM Role for Enhanced Monitoring
# =============================================================================

resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name = "${var.mysql_identifier}-rds-monitoring"
  tags = local.base_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# =============================================================================
# MySQL Parameter Group
# =============================================================================

resource "aws_db_parameter_group" "mysql" {
  name   = "${var.mysql_identifier}-params"
  family = var.parameter_group_family
  tags   = local.base_tags

  # Grant stored function/trigger creation to the default user when binlog is on
  parameter {
    name  = "log_bin_trust_function_creators"
    value = "1"
  }
}

# =============================================================================
# RDS MySQL Instance
# =============================================================================

resource "aws_db_instance" "mysql" {
  identifier           = var.mysql_identifier
  tags                 = local.base_tags
  instance_class       = var.instance_class
  port                 = var.port
  password             = var.password
  db_name              = var.database_name
  parameter_group_name = aws_db_parameter_group.mysql.name
  storage_encrypted    = var.encrypt_disk

  # ---------------------------------------------------------------------------
  # Snapshot restore vs. fresh creation
  # ---------------------------------------------------------------------------
  snapshot_identifier = local.is_snapshot_restore ? var.snapshot_identifier : null
  allocated_storage   = local.is_snapshot_restore ? null : var.disk_size
  storage_type        = local.is_snapshot_restore ? null : var.storage_type
  username            = local.is_snapshot_restore ? null : var.username
  engine_version      = local.is_snapshot_restore ? null : var.mysql_version
  engine              = local.is_snapshot_restore ? null : "mysql"
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
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

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
    ]
  }
}
