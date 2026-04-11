module "aks_openwebui" {
  source = "../.."

  project_name      = var.project_name
  environment       = var.environment
  location          = var.location
  letsencrypt_email = var.letsencrypt_email
  tags              = var.tags
}

output "app_url" {
  description = "HTTPS URL for Open WebUI"
  value       = module.aks_openwebui.app_url
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks_openwebui.aks_cluster_name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.aks_openwebui.resource_group_name
}
