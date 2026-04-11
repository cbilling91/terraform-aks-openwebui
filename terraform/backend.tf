# Backend configuration for Terraform state storage in Azure Storage
# This file should be configured after running the bootstrap-backend.sh script

# Uncomment and fill in after running bootstrap-backend.sh:
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-terraform-state"
#     storage_account_name = "tfstate<unique-id>"
#     container_name       = "tfstate"
#     key                  = "aks-openwebui-poc.tfstate"
#   }
# }

# Note: For initial deployment, you can use local state by leaving this commented.
# After running bootstrap-backend.sh, uncomment the above block with the correct values.

