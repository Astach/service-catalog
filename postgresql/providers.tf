# -----------------------------------------------------------------------------
# PostgreSQL RDS - Provider Configuration
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# The AWS provider is expected to be configured by the caller.
# When using this module via Qovery Terraform Service, set your AWS credentials
# in the Qovery environment variables or provider block in a root module.
