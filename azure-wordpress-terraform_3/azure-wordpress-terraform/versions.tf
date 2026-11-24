###############################################################################
# STEP 0 - Terraform & provider configuration
###############################################################################
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.20"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Recommended for teams: keep state in an Azure Storage account.
  # Create the storage account once, then uncomment and run `terraform init -migrate-state`.
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstateuncf001"
  #   container_name       = "tfstate"
  #   key                  = "wordpress-prod.tfstate"
  #   use_azuread_auth     = true
  # }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}
