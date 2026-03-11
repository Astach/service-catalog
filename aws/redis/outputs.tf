# -----------------------------------------------------------------------------
# Redis (ElastiCache) - Outputs
#
# All output names use the QSM_ prefix for Service Catalog integration.
# Example: service "my-cache" -> MY_CACHE_REDIS_HOST
# -----------------------------------------------------------------------------

output "QSM_REDIS_ID" {
  description = "The ElastiCache replication group ID"
  value       = aws_elasticache_replication_group.redis.id
}

output "QSM_REDIS_REPLICATION_GROUP_ID" {
  description = "The replication group identifier"
  value       = aws_elasticache_replication_group.redis.replication_group_id
}

output "QSM_REDIS_HOST" {
  description = "The primary endpoint address (read/write)"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "QSM_REDIS_READER_ENDPOINT" {
  description = "The reader endpoint address (load-balanced across replicas)"
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
}

output "QSM_REDIS_PORT" {
  description = "The Redis port"
  value       = var.port
}

output "QSM_REDIS_ARN" {
  description = "The ARN of the ElastiCache replication group"
  value       = aws_elasticache_replication_group.redis.arn
}

output "QSM_REDIS_CONNECTION_STRING" {
  description = "Redis connection string (without password, with TLS)"
  value       = "rediss://${aws_elasticache_replication_group.redis.primary_endpoint_address}:${var.port}"
  sensitive   = false
}

output "QSM_REDIS_VPC_ID" {
  description = "The VPC ID where ElastiCache is deployed"
  value       = local.vpc_id
}

output "QSM_REDIS_SECURITY_GROUP_ID" {
  description = "The security group ID attached to the ElastiCache cluster"
  value       = length(var.security_group_ids) == 0 ? aws_security_group.elasticache[0].id : var.security_group_ids[0]
}
