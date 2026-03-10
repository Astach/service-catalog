# -----------------------------------------------------------------------------
# MongoDB (DocumentDB) - Main Resources
#
# AWS DocumentDB is a cluster-based service (cluster + N instances), unlike
# RDS which uses a single db_instance resource.
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
  security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.docdb[0].id]
  subnet_group_name  = var.docdb_subnet_group_name != "" ? var.docdb_subnet_group_name : aws_docdb_subnet_group.docdb[0].name

  is_snapshot_restore  = var.snapshot_identifier != ""
  final_snap_timestamp = replace(timestamp(), "/[- TZ:]/", "")
  final_snapshot_name  = "${var.final_snapshot_name}-${local.final_snap_timestamp}"

  # Look up AZs from subnets for the cluster availability_zones parameter
  availability_zones = distinct([for s in data.aws_subnet.selected : s.availability_zone])

  base_tags = merge(
    {
      "ManagedBy"     = "terraform"
      "Service"       = "documentdb"
      "Identifier"    = var.documentdb_identifier
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
# Subnet data lookups (to resolve AZs)
# =============================================================================

data "aws_subnet" "selected" {
  for_each = toset(local.subnet_ids)
  id       = each.value
}

# =============================================================================
# Network Resources
# =============================================================================

resource "aws_security_group" "docdb" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name        = "${var.documentdb_identifier}-docdb-sg"
  description = "Security group for DocumentDB ${var.documentdb_identifier}"
  vpc_id      = local.vpc_id
  tags        = merge(local.base_tags, { "Name" = "${var.documentdb_identifier}-docdb-sg" })

  ingress {
    description     = "DocumentDB from EKS cluster"
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

resource "aws_docdb_subnet_group" "docdb" {
  count = var.docdb_subnet_group_name == "" ? 1 : 0

  name       = "${var.documentdb_identifier}-subnet-group"
  subnet_ids = local.subnet_ids
  tags       = merge(local.base_tags, { "Name" = "${var.documentdb_identifier}-subnet-group" })
}

# =============================================================================
# DocumentDB Cluster
# =============================================================================

resource "aws_docdb_cluster" "cluster" {
  cluster_identifier = var.documentdb_identifier
  tags               = local.base_tags

  engine_version     = var.documentdb_version
  port               = var.port
  master_password    = var.password
  storage_encrypted  = var.encrypt_disk

  # Snapshot restore vs. fresh creation
  snapshot_identifier = local.is_snapshot_restore ? var.snapshot_identifier : null
  master_username     = local.is_snapshot_restore ? null : var.username
  engine              = local.is_snapshot_restore ? null : "docdb"

  # Network
  availability_zones     = local.availability_zones
  db_subnet_group_name   = local.subnet_group_name
  vpc_security_group_ids = local.security_group_ids

  # Maintenance
  apply_immediately = var.apply_changes_now

  # Backup
  backup_retention_period   = var.backup_retention_period
  preferred_backup_window   = var.preferred_backup_window
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : local.final_snapshot_name

  timeouts {
    create = "60m"
    update = "120m"
    delete = "60m"
  }

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier,
      availability_zones,
    ]
  }
}

# =============================================================================
# DocumentDB Cluster Instances
# =============================================================================

resource "aws_docdb_cluster_instance" "instances" {
  count = var.instances_number

  cluster_identifier = aws_docdb_cluster.cluster.id
  identifier         = "${var.documentdb_identifier}-${count.index}"
  instance_class     = var.instance_class
  tags               = local.base_tags

  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  preferred_maintenance_window = var.preferred_maintenance_window
}
