# -----------------------------------------------------------------------------
# PostgreSQL RDS - Outputs
#
# All output names use the QSM_ prefix for Service Catalog integration.
# When provisioned via the catalog, q-core strips the "QSM_" prefix and
# prepends the user-given service name to create environment variables.
# Example: service "my-db" -> MY_DB_POSTGRESQL_HOST
# -----------------------------------------------------------------------------

output "QSM_POSTGRESQL_ID" {
  description = "The RDS instance ID"
  value       = aws_db_instance.postgresql.id
}

output "QSM_POSTGRESQL_IDENTIFIER" {
  description = "The RDS instance identifier"
  value       = aws_db_instance.postgresql.identifier
}

output "QSM_POSTGRESQL_ENDPOINT" {
  description = "The connection endpoint (hostname:port)"
  value       = aws_db_instance.postgresql.endpoint
}

output "QSM_POSTGRESQL_HOST" {
  description = "The RDS instance hostname (without port)"
  value       = aws_db_instance.postgresql.address
}

output "QSM_POSTGRESQL_PORT" {
  description = "The database port"
  value       = aws_db_instance.postgresql.port
}

output "QSM_POSTGRESQL_DATABASE" {
  description = "The name of the default database"
  value       = aws_db_instance.postgresql.db_name
}

output "QSM_POSTGRESQL_USERNAME" {
  description = "The master username"
  value       = aws_db_instance.postgresql.username
}

output "QSM_POSTGRESQL_ARN" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.postgresql.arn
}

output "QSM_POSTGRESQL_RESOURCE_ID" {
  description = "The RDS Resource ID (for IAM auth and CloudWatch)"
  value       = aws_db_instance.postgresql.resource_id
}

output "QSM_POSTGRESQL_CONNECTION_STRING" {
  description = "PostgreSQL connection string (without password)"
  value       = "postgresql://${aws_db_instance.postgresql.username}@${aws_db_instance.postgresql.address}:${aws_db_instance.postgresql.port}/${aws_db_instance.postgresql.db_name}"
  sensitive   = false
}

output "QSM_POSTGRESQL_VPC_ID" {
  description = "The VPC ID where the RDS instance is deployed"
  value       = local.vpc_id
}

output "QSM_POSTGRESQL_SECURITY_GROUP_ID" {
  description = "The security group ID attached to the RDS instance"
  value       = length(var.security_group_ids) == 0 ? aws_security_group.rds[0].id : var.security_group_ids[0]
}
