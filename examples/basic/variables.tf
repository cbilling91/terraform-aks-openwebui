variable "project_name" {
  description = "Name of the project — used for all resource naming and the app DNS label"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, demo, prod)"
  type        = string
  default     = "demo"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate registration and expiry notices"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all Azure resources"
  type        = map(string)
  default     = {}
}
