# -----------------------------------------------------------------------------
# Redis (ElastiCache) - Main Resources
#
# Uses aws_elasticache_replication_group with TLS + auth token (modern path).
# The legacy aws_elasticache_cluster (Redis 5.0, no TLS) is not supported.
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
  security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.elasticache[0].id]
  subnet_group_name  = var.elasticache_subnet_group_name != "" ? var.elasticache_subnet_group_name : aws_elasticache_subnet_group.redis[0].name

  final_snap_timestamp = replace(timestamp(), "/[- TZ:]/", "")
  final_snapshot_name  = "${var.final_snapshot_name}-${local.final_snap_timestamp}"

  base_tags = merge(
    {
      "ManagedBy"     = "terraform"
      "Service"       = "redis"
      "Identifier"    = var.elasticache_identifier
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

resource "aws_security_group" "elasticache" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name        = "${var.elasticache_identifier}-redis-sg"
  description = "Security group for ElastiCache Redis ${var.elasticache_identifier}"
  vpc_id      = local.vpc_id
  tags        = merge(local.base_tags, { "Name" = "${var.elasticache_identifier}-redis-sg" })

  ingress {
    description     = "Redis from EKS cluster"
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

resource "aws_elasticache_subnet_group" "redis" {
  count = var.elasticache_subnet_group_name == "" ? 1 : 0

  name       = "${var.elasticache_identifier}-subnet-group"
  subnet_ids = local.subnet_ids
  tags       = merge(local.base_tags, { "Name" = "${var.elasticache_identifier}-subnet-group" })
}

# =============================================================================
# ElastiCache Replication Group
# =============================================================================

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = var.elasticache_identifier
  description          = "ElastiCache Redis - ${var.elasticache_identifier}"
  tags                 = local.base_tags

  # Engine
  engine_version       = var.elasticache_version
  node_type            = var.node_type
  port                 = var.port
  parameter_group_name = var.parameter_group_name
  num_cache_clusters   = var.num_cache_clusters

  # Auth & encryption
  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token                 = var.auth_token
  at_rest_encryption_enabled = var.encrypt_disk

  # Network
  subnet_group_name  = local.subnet_group_name
  security_group_ids = local.security_group_ids

  # Maintenance
  apply_immediately    = var.apply_changes_now
  maintenance_window   = var.preferred_maintenance_window

  # Backup
  snapshot_window          = var.snapshot_window
  snapshot_retention_limit = var.snapshot_retention_limit
  final_snapshot_identifier = var.skip_final_snapshot ? null : local.final_snapshot_name

  # Snapshot restore
  snapshot_name = var.snapshot_identifier != "" ? var.snapshot_identifier : null

  lifecycle {
    ignore_changes = [
      engine_version,
      final_snapshot_identifier,
    ]
  }
}
