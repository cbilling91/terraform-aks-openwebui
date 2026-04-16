
provider "kubernetes" {
  host                   = try(module.aks.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.aks.cluster_ca_certificate), "")
  client_certificate     = try(base64decode(module.aks.client_certificate), "")
  client_key             = try(base64decode(module.aks.client_key), "")
}

provider "helm" {
  kubernetes {
    host                   = try(module.aks.cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.aks.cluster_ca_certificate), "")
    client_certificate     = try(base64decode(module.aks.client_certificate), "")
    client_key             = try(base64decode(module.aks.client_key), "")
  }
}

provider "kubectl" {
  host                   = try(module.aks.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.aks.cluster_ca_certificate), "")
  client_certificate     = try(base64decode(module.aks.client_certificate), "")
  client_key             = try(base64decode(module.aks.client_key), "")
  load_config_file       = false
}

provider "azurerm" {
  # Set ARM_SUBSCRIPTION_ID environment variable instead of hardcoding here
  # e.g.: export ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
