# -----------------------------------------------------------------------------
# V2 Blueprint: Managed PostgreSQL
#
# Uses the Qovery Terraform provider to create a managed PostgreSQL database.
# This is a V2 blueprint -- the engine runs `terraform plan` first, the user
# reviews the plan, then approves to apply.
# -----------------------------------------------------------------------------

resource "qovery_database" "main" {
  environment_id = var.qovery_environment_id
  name           = var.database_name
  type           = "POSTGRESQL"
  version        = var.postgresql_version
  mode           = "MANAGED"

  instance_type  = var.instance_type
  accessibility  = var.accessibility
  storage        = var.storage_gb
}
