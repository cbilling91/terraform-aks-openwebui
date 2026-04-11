output "app_url" {
  description = "HTTPS URL for Open WebUI"
  value       = "https://${local.app_fqdn}"
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.resource_group.resource_group_name
}

output "openai_deployment_name" {
  description = "Name of the Azure OpenAI deployment"
  value       = module.ai_foundry.deployment_name
}

output "kube_config_raw" {
  description = "Raw kubeconfig for kubectl access"
  value       = module.aks.kube_config
  sensitive   = true
}
