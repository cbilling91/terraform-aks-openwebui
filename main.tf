locals {
  resource_group_name = "rg-${var.project_name}-${var.environment}"
  openai_account_name = var.project_name
  aks_cluster_name    = var.project_name
  aks_dns_prefix      = var.project_name
  app_dns_label       = var.project_name
  app_fqdn            = "${local.app_dns_label}.${var.location}.cloudapp.azure.com"
}

# Generate a unique suffix for globally unique resource names
resource "random_string" "unique_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group Module
module "resource_group" {
  source = "./modules/resource-group"

  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = var.tags
}
