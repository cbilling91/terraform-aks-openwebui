# Azure AI Foundry (OpenAI) Module
module "ai_foundry" {
  source = "./modules/ai-foundry"

  openai_account_name = "${local.openai_account_name}-${random_string.unique_suffix.result}"
  location            = var.location
  resource_group_name = module.resource_group.resource_group_name

  deployment_name = var.openai_model_name
  model_name      = var.openai_model_name
  capacity        = 10 # 10K TPM for cost control

  tags = var.tags

  depends_on = [module.resource_group]
}
