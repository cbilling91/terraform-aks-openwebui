resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  sku_tier            = "Free"

  # Kubernetes version
  kubernetes_version = var.kubernetes_version

  # System node pool (regular nodes for system workloads)
  default_node_pool {
    name                         = "system"
    node_count                   = var.system_node_count
    vm_size                      = var.system_node_vm_size
    type                         = "VirtualMachineScaleSets"
    enable_auto_scaling          = false
    temporary_name_for_rotation  = "tmpsystem"

    # System pool specific settings
    only_critical_addons_enabled = true

    tags = merge(
      var.tags,
      {
        "node-type" = "system"
      }
    )
  }

  # Managed identity for the cluster
  identity {
    type = "SystemAssigned"
  }

  # Network profile using kubenet (cheaper than Azure CNI)
  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
    network_policy    = "calico"
  }

  oidc_issuer_enabled = true

  tags = var.tags
}

# User node pool (spot instances for application workloads)
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_node_vm_size
  node_count            = var.user_node_count

  # Spot instance configuration for cost savings
  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1 # Use current on-demand price as max

  # Mode set to User (not system)
  mode                = "User"
  enable_auto_scaling = false

  # Node labels to identify spot nodes
  node_labels = {
    "workload-type"                          = "spot"
    "kubernetes.azure.com/scalesetpriority"  = "spot"
  }

  # Taints to ensure only workloads that tolerate spot can schedule here
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  tags = merge(
    var.tags,
    {
      "node-type" = "user-spot"
    }
  )
}
