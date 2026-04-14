resource "azurerm_cognitive_account" "openai" {
  name                = var.openai_account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "OpenAI"
  sku_name            = "S0"

  tags = var.tags

  # Public network access required for POC demo
  public_network_access_enabled = true

  # Use API key authentication for simplicity
  custom_subdomain_name = var.openai_account_name
}

resource "azurerm_cognitive_deployment" "model" {
  name                 = var.deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format = "OpenAI"
    name   = var.model_name
  }

  sku {
    name     = var.sku_name
    capacity = var.capacity
  }

  version_upgrade_option = "OnceNewDefaultVersionAvailable"
}
