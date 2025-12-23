terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.56.0"
    }
  }
  required_version = ">=1.14.1"
}

provider "azurerm" {
  features {}
  #subscription_id = "<subscription_id>"
}