# -----------------------------------------------------------------------------
# Injected Variables (auto-filled by q-core, never shown to the user)
# -----------------------------------------------------------------------------

variable "qovery_environment_id" {
  description = "Qovery environment ID where the database will be created"
  type        = string
}

# -----------------------------------------------------------------------------
# User Variables (shown in the provisioning form)
# -----------------------------------------------------------------------------

variable "database_name" {
  description = "Name for the database service in Qovery"
  type        = string
}

variable "postgresql_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16"
}

variable "instance_type" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "storage_gb" {
  description = "Storage size in GB"
  type        = number
  default     = 10
}

variable "accessibility" {
  description = "Database accessibility: PRIVATE or PUBLIC"
  type        = string
  default     = "PRIVATE"
}
