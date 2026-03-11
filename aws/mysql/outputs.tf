# -----------------------------------------------------------------------------
# MySQL RDS - Outputs
#
# All output names use the QSM_ prefix for Service Catalog integration.
# Example: service "my-db" -> MY_DB_MYSQL_HOST
# -----------------------------------------------------------------------------

output "QSM_MYSQL_ID" {
  description = "The RDS instance ID"
  value       = aws_db_instance.mysql.id
}

output "QSM_MYSQL_IDENTIFIER" {
  description = "The RDS instance identifier"
  value       = aws_db_instance.mysql.identifier
}

output "QSM_MYSQL_ENDPOINT" {
  description = "The connection endpoint (hostname:port)"
  value       = aws_db_instance.mysql.endpoint
}

output "QSM_MYSQL_HOST" {
  description = "The RDS instance hostname (without port)"
  value       = aws_db_instance.mysql.address
}

output "QSM_MYSQL_PORT" {
  description = "The database port"
  value       = aws_db_instance.mysql.port
}

output "QSM_MYSQL_DATABASE" {
  description = "The name of the default database"
  value       = aws_db_instance.mysql.db_name
}

output "QSM_MYSQL_USERNAME" {
  description = "The master username"
  value       = aws_db_instance.mysql.username
}

output "QSM_MYSQL_ARN" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.mysql.arn
}

output "QSM_MYSQL_CONNECTION_STRING" {
  description = "MySQL connection string (without password)"
  value       = "mysql://${aws_db_instance.mysql.username}@${aws_db_instance.mysql.address}:${aws_db_instance.mysql.port}/${aws_db_instance.mysql.db_name}"
  sensitive   = false
}

output "QSM_MYSQL_VPC_ID" {
  description = "The VPC ID where the RDS instance is deployed"
  value       = local.vpc_id
}

output "QSM_MYSQL_SECURITY_GROUP_ID" {
  description = "The security group ID attached to the RDS instance"
  value       = length(var.security_group_ids) == 0 ? aws_security_group.rds[0].id : var.security_group_ids[0]
}
