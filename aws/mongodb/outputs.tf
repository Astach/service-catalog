# -----------------------------------------------------------------------------
# MongoDB (DocumentDB) - Outputs
#
# All output names use the QSM_ prefix for Service Catalog integration.
# Example: service "my-mongo" -> MY_MONGO_MONGODB_HOST
# -----------------------------------------------------------------------------

output "QSM_MONGODB_CLUSTER_ID" {
  description = "The DocumentDB cluster ID"
  value       = aws_docdb_cluster.cluster.id
}

output "QSM_MONGODB_CLUSTER_IDENTIFIER" {
  description = "The DocumentDB cluster identifier"
  value       = aws_docdb_cluster.cluster.cluster_identifier
}

output "QSM_MONGODB_HOST" {
  description = "The cluster endpoint (writer)"
  value       = aws_docdb_cluster.cluster.endpoint
}

output "QSM_MONGODB_READER_ENDPOINT" {
  description = "The cluster reader endpoint (load-balanced across read replicas)"
  value       = aws_docdb_cluster.cluster.reader_endpoint
}

output "QSM_MONGODB_PORT" {
  description = "The database port"
  value       = aws_docdb_cluster.cluster.port
}

output "QSM_MONGODB_USERNAME" {
  description = "The master username"
  value       = aws_docdb_cluster.cluster.master_username
}

output "QSM_MONGODB_ARN" {
  description = "The ARN of the DocumentDB cluster"
  value       = aws_docdb_cluster.cluster.arn
}

output "QSM_MONGODB_INSTANCE_IDS" {
  description = "The IDs of the DocumentDB cluster instances"
  value       = aws_docdb_cluster_instance.instances[*].id
}

output "QSM_MONGODB_INSTANCE_ENDPOINTS" {
  description = "The endpoints of each DocumentDB cluster instance"
  value       = aws_docdb_cluster_instance.instances[*].endpoint
}

output "QSM_MONGODB_CONNECTION_STRING" {
  description = "MongoDB connection string (without password). Use with ?tls=true&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
  value       = "mongodb://${aws_docdb_cluster.cluster.master_username}@${aws_docdb_cluster.cluster.endpoint}:${aws_docdb_cluster.cluster.port}"
  sensitive   = false
}

output "QSM_MONGODB_VPC_ID" {
  description = "The VPC ID where the DocumentDB cluster is deployed"
  value       = local.vpc_id
}

output "QSM_MONGODB_SECURITY_GROUP_ID" {
  description = "The security group ID attached to the DocumentDB cluster"
  value       = length(var.security_group_ids) == 0 ? aws_security_group.docdb[0].id : var.security_group_ids[0]
}
