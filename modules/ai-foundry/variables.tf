variable "openai_account_name" {
  description = "Name of the Azure OpenAI account (must be globally unique)"
  type        = string
}

variable "location" {
  description = "Azure region for the OpenAI service"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "deployment_name" {
  description = "Name of the model deployment"
  type        = string
  default     = "gpt-4o-deployment"
}

variable "model_name" {
  description = "Name of the model to deploy"
  type        = string
  default     = "gpt-4o"
}

variable "model_version" {
  description = "Version of the model to deploy"
  type        = string
  default     = "2024-11-20"
}

variable "capacity" {
  description = "Deployment capacity in TPM (tokens per minute) - 10K for cost control"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
