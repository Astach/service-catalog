# -----------------------------------------------------------------------------
# PostgreSQL RDS - Outputs
#
# Output names are clean lowercase identifiers. When provisioned via the
# catalog, q-core prepends the user-given service name to create
# environment variables.
# Example: service "my-db" -> MY_DB_POSTGRESQL_HOST
# -----------------------------------------------------------------------------

output "postgresql_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.postgresql.id
}

output "postgresql_identifier" {
  description = "The RDS instance identifier"
  value       = aws_db_instance.postgresql.identifier
}

output "postgresql_endpoint" {
  description = "The connection endpoint (hostname:port)"
  value       = aws_db_instance.postgresql.endpoint
}

output "postgresql_host" {
  description = "The RDS instance hostname (without port)"
  value       = aws_db_instance.postgresql.address
}

output "postgresql_port" {
  description = "The database port"
  value       = aws_db_instance.postgresql.port
}

output "postgresql_database" {
  description = "The name of the default database"
  value       = aws_db_instance.postgresql.db_name
}

output "postgresql_username" {
  description = "The master username"
  value       = aws_db_instance.postgresql.username
}

output "postgresql_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.postgresql.arn
}

output "postgresql_resource_id" {
  description = "The RDS Resource ID (for IAM auth and CloudWatch)"
  value       = aws_db_instance.postgresql.resource_id
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string (without password)"
  value       = "postgresql://${aws_db_instance.postgresql.username}@${aws_db_instance.postgresql.address}:${aws_db_instance.postgresql.port}/${aws_db_instance.postgresql.db_name}"
  sensitive   = false
}

output "postgresql_vpc_id" {
  description = "The VPC ID where the RDS instance is deployed"
  value       = local.vpc_id
}

output "postgresql_security_group_id" {
  description = "The security group ID attached to the RDS instance"
  value       = length(var.security_group_ids) == 0 ? aws_security_group.rds[0].id : var.security_group_ids[0]
}
