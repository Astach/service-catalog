# -----------------------------------------------------------------------------
# PostgreSQL RDS - Outputs
# -----------------------------------------------------------------------------

output "id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.postgresql.id
}

output "identifier" {
  description = "The RDS instance identifier"
  value       = aws_db_instance.postgresql.identifier
}

output "endpoint" {
  description = "The connection endpoint (hostname:port)"
  value       = aws_db_instance.postgresql.endpoint
}

output "hostname" {
  description = "The RDS instance hostname (without port)"
  value       = aws_db_instance.postgresql.address
}

output "port" {
  description = "The database port"
  value       = aws_db_instance.postgresql.port
}

output "database_name" {
  description = "The name of the default database"
  value       = aws_db_instance.postgresql.db_name
}

output "username" {
  description = "The master username"
  value       = aws_db_instance.postgresql.username
}

output "arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.postgresql.arn
}

output "resource_id" {
  description = "The RDS Resource ID (for IAM auth and CloudWatch)"
  value       = aws_db_instance.postgresql.resource_id
}

output "connection_string" {
  description = "PostgreSQL connection string (without password)"
  value       = "postgresql://${aws_db_instance.postgresql.username}@${aws_db_instance.postgresql.address}:${aws_db_instance.postgresql.port}/${aws_db_instance.postgresql.db_name}"
  sensitive   = false
}
