terraform {
  backend "azurerm" {
    resource_group_name  = "rg-web-app-tfstate"
    storage_account_name = "tfstatedev22337"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}