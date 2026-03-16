terraform {
  required_version = ">= 1.5"

  required_providers {
    qovery = {
      source  = "Qovery/qovery"
      version = "~> 0.61"
    }
  }
}

provider "qovery" {
  # Authenticated via QOVERY_API_TOKEN environment variable,
  # injected by q-core from organization.api_token.
}
