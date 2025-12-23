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
  subscription_id = "998c91fb-03d5-4638-ab92-c44e71328378"
}