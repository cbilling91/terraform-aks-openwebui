# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.resource_group.resource_group_name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = module.resource_group.location
}

# Azure OpenAI Outputs
output "openai_account_name" {
  description = "Azure OpenAI account name (with unique suffix)"
  value       = "${var.openai_account_name}-${random_string.unique_suffix.result}"
}

output "openai_endpoint" {
  description = "Azure OpenAI endpoint URL"
  value       = module.ai_foundry.openai_endpoint
}

output "openai_api_key" {
  description = "Azure OpenAI API key"
  value       = module.ai_foundry.openai_api_key
  sensitive   = true
}

output "openai_deployment_name" {
  description = "Name of the GPT-4 deployment"
  value       = module.ai_foundry.deployment_name
}

output "openai_api_version" {
  description = "Azure OpenAI API version"
  value       = module.ai_foundry.openai_api_version
}

# AKS Outputs
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = module.aks.cluster_fqdn
}

output "aks_node_resource_group" {
  description = "Resource group containing AKS node resources"
  value       = module.aks.node_resource_group
}

output "kube_config_raw" {
  description = "Raw kubeconfig for kubectl access"
  value       = module.aks.kube_config
  sensitive   = true
}

# Networking Outputs
output "app_url" {
  description = "HTTPS URL for Open WebUI"
  value       = "https://${local.app_fqdn}"
}

output "app_fqdn" {
  description = "Fully qualified domain name for Open WebUI"
  value       = local.app_fqdn
}

# Open WebUI Helm Release Outputs
output "open_webui_status" {
  description = "Status of the Open WebUI Helm release"
  value       = helm_release.open_webui.status
}

output "open_webui_namespace" {
  description = "Namespace where Open WebUI is deployed"
  value       = helm_release.open_webui.namespace
}

# Connection Instructions
output "next_steps" {
  description = "Next steps to access Open WebUI"
  value = <<-EOT

    ========================================
    Deployment Complete!
    ========================================

    All infrastructure has been deployed via Terraform, including:
    ✅ Azure OpenAI
    ✅ AKS Cluster (Free tier with mixed node pools)
    ✅ Traefik Gateway (HTTPS via Let's Encrypt)
    ✅ Open WebUI (deployed via Helm)

    Open WebUI URL: https://${local.app_fqdn}

    Note: TLS certificate provisioning takes 2-3 minutes after deployment.
    Check certificate status: kubectl get certificate -n traefik

    Useful commands:
       kubectl get pods -n default
       kubectl get httproute -n default
       kubectl get certificate -n traefik
       kubectl logs -l app.kubernetes.io/name=open-webui -n default
       helm list -A

    To destroy all resources:
       terraform destroy
  EOT
}

