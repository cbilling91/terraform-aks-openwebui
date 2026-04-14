output "openai_endpoint" {
  description = "Endpoint URL for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_api_key" {
  description = "Primary API key for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_account_name" {
  description = "Name of the Azure OpenAI account"
  value       = azurerm_cognitive_account.openai.name
}

output "deployment_name" {
  description = "Name of the GPT-4 model deployment"
  value       = azurerm_cognitive_deployment.model.name
}

output "model_name" {
  description = "Name of the deployed model"
  value       = var.model_name
}

output "openai_api_version" {
  description = "API version for Azure OpenAI"
  value       = "2024-12-01-preview"
}
