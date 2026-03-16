output "database_id" {
  description = "Qovery database resource ID"
  value       = qovery_database.main.id
}

output "database_internal_host" {
  description = "Database internal hostname"
  value       = qovery_database.main.internal_host
}

output "database_external_host" {
  description = "Database external hostname (if publicly accessible)"
  value       = qovery_database.main.external_host
}

output "database_port" {
  description = "Database port"
  value       = qovery_database.main.port
}

output "database_login" {
  description = "Database login"
  value       = qovery_database.main.login
}

output "database_password" {
  description = "Database password"
  value       = qovery_database.main.password
  sensitive   = true
}
