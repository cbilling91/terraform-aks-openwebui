output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "kube_config" {
  description = "Kubernetes configuration for kubectl access"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kube_config_admin" {
  description = "Kubernetes admin configuration"
  value       = azurerm_kubernetes_cluster.main.kube_admin_config_raw
  sensitive   = true
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "node_resource_group" {
  description = "Resource group containing AKS node resources"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "cluster_endpoint" {
  description = "Endpoint for the Kubernetes API server"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
}

output "cluster_ca_certificate" {
  description = "Base64 encoded certificate authority data"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "client_certificate" {
  description = "Base64 encoded client certificate"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Base64 encoded client key"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].client_key
  sensitive   = true
}
