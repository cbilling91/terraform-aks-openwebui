variable "project_name" {
  description = "Name of the project - used for resource naming"
  type        = string
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


variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate registration and expiry notices"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.34.4"
}


variable "traefik_chart_version" {
  description = "Helm chart version for Traefik"
  type        = string
  default     = "39.0.7"
}

variable "cert_manager_chart_version" {
  description = "Helm chart version for cert-manager"
  type        = string
  default     = "v1.20.1"
}

variable "open_webui_chart_version" {
  description = "Helm chart version for Open WebUI"
  type        = string
  default     = "13.3.1"
}

variable "litellm_image" {
  description = "LiteLLM container image (repository:tag)"
  type        = string
  default     = "ghcr.io/berriai/litellm:v1.82.3"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "AKS-OpenWebUI-POC"
    Environment = "Demo"
    ManagedBy   = "Terraform"
    Purpose     = "CaseStudy"
  }
}
