variable "project_name" {
  description = "Name of the project - used for resource naming"
  type        = string
  default     = "aks-openwebui-poc"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-aks-openwebui-poc-demo"
}

variable "openai_account_name" {
  description = "Name of the Azure OpenAI account (will have unique suffix appended automatically)"
  type        = string
  default     = "openai-aks-openwebui"
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-aks-openwebui-poc"
}

variable "aks_dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
  default     = "aks-openwebui-poc"
}

variable "openai_model_name" {
  description = "Azure OpenAI model to deploy (e.g., gpt-4o, gpt-4, gpt-35-turbo)"
  type        = string
  default     = "gpt-4o"
}

variable "openai_model_version" {
  description = "Version of the OpenAI model to deploy"
  type        = string
  default     = "2024-11-20"
}

variable "app_dns_label" {
  description = "DNS label for the ingress public IP — becomes <label>.<region>.cloudapp.azure.com"
  type        = string
  default     = "aks-openwebui-poc"
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate registration and expiry notices"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "aks-openwebui-POC"
    Environment = "Demo"
    ManagedBy   = "Terraform"
    Purpose     = "CaseStudy"
  }
}
