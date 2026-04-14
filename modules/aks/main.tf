resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  sku_tier            = "Free"

  kubernetes_version = var.kubernetes_version

  default_node_pool {
    name                        = "system"
    node_count                  = 1
    vm_size                     = var.node_vm_size
    type                        = "VirtualMachineScaleSets"
    auto_scaling_enabled        = false
    temporary_name_for_rotation = "tmpsystem"

    tags = var.tags
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
    network_policy    = "calico"
  }

  oidc_issuer_enabled = true

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_node_vm_size
  node_count            = var.user_node_count
  mode                  = "User"

  priority        = var.spot_instances ? "Spot" : "Regular"
  eviction_policy = var.spot_instances ? "Delete" : null
  spot_max_price  = var.spot_instances ? -1 : null

  tags = var.tags
}
