locals {
  resource_group_name = "rg-${var.project_name}-${var.environment}"
  openai_account_name = var.project_name
  aks_cluster_name    = var.project_name
  aks_dns_prefix      = var.project_name
  app_dns_label       = var.project_name
  app_fqdn            = "${local.app_dns_label}.${var.location}.cloudapp.azure.com"
}

# Generate a unique suffix for globally unique resource names
resource "random_string" "unique_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Resource Group Module
module "resource_group" {
  source = "./modules/resource-group"

  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = var.tags
}

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

# AKS Cluster Module
module "aks" {
  source = "./modules/aks"

  cluster_name        = local.aks_cluster_name
  location            = var.location
  resource_group_name = module.resource_group.resource_group_name
  dns_prefix          = local.aks_dns_prefix

  kubernetes_version = var.kubernetes_version
  spot_instances     = var.spot_instances
  user_node_vm_size  = var.user_node_vm_size
  user_node_count    = var.user_node_count

  tags = var.tags

  depends_on = [module.resource_group]
}

# Static public IP for Traefik — placed in AKS node resource group where the
# cluster identity has automatic permissions
resource "azurerm_public_ip" "ingress" {
  name                = "pip-${var.project_name}-ingress"
  location            = var.location
  resource_group_name = module.aks.node_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = local.app_dns_label
  tags                = var.tags

  depends_on = [module.aks]
}

# Traefik with Gateway API support enabled
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://helm.traefik.io/traefik"
  chart            = "traefik"
  version          = var.traefik_chart_version
  namespace        = "traefik"
  create_namespace = true
  timeout          = 300

  values = [
    yamlencode({
      deployment = {
        tolerations = [
          {
            key      = "kubernetes.azure.com/scalesetpriority"
            operator = "Equal"
            value    = "spot"
            effect   = "NoSchedule"
          }
        ]
      }

      providers = {
        kubernetesGateway = {
          enabled = true
        }
      }

      service = {
        annotations = {
          "service.beta.kubernetes.io/azure-load-balancer-resource-group" = module.aks.node_resource_group
        }
        spec = {
          loadBalancerIP = azurerm_public_ip.ingress.ip_address
        }
      }

    })
  ]

  depends_on = [module.aks, azurerm_public_ip.ingress]
}

# cert-manager for TLS certificate lifecycle management
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  namespace        = "cert-manager"
  create_namespace = true
  timeout          = 300

  values = [
    yamlencode({
      installCRDs = true

      tolerations = [
        {
          key      = "kubernetes.azure.com/scalesetpriority"
          operator = "Equal"
          value    = "spot"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

  depends_on = [module.aks]
}

resource "kubectl_manifest" "letsencrypt_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-prod-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                ingressClassName = "traefik"
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "traefik_gatewayclass" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name = "traefik"
    }
    spec = {
      controllerName = "traefik.io/gateway-controller"
    }
  })

  depends_on = [helm_release.traefik]
}

resource "kubectl_manifest" "traefik_gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "traefik-gateway"
      namespace = "traefik"
    }
    spec = {
      gatewayClassName = "traefik"
      listeners = [
        {
          name     = "http"
          port     = 8000
          protocol = "HTTP"
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "https"
          port     = 8443
          protocol = "HTTPS"
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                kind      = "Secret"
                name      = "open-webui-tls"
                namespace = "traefik"
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.traefik_gatewayclass]
}

# TLS certificate for the app domain — issued by Let's Encrypt, stored as a
# secret in the traefik namespace where the Gateway can reference it
resource "kubectl_manifest" "open_webui_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "open-webui-tls"
      namespace = "traefik"
    }
    spec = {
      secretName = "open-webui-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [local.app_fqdn]
    }
  })

  depends_on = [kubectl_manifest.letsencrypt_issuer, kubectl_manifest.traefik_gateway]
}

# Kubernetes Secret for Azure OpenAI API Key
resource "kubernetes_secret" "azure_openai" {
  metadata {
    name      = "azure-openai-secret"
    namespace = "default"
  }

  data = {
    api-key = module.ai_foundry.openai_api_key
  }

  depends_on = [module.aks]
}

# LiteLLM — OpenAI-compatible proxy for Azure OpenAI.
# Azure OpenAI uses a different URL structure (/openai/deployments/{name}/chat/completions)
# and requires api-version as a query param. Open WebUI expects standard OpenAI API format.
# LiteLLM bridges this gap, exposing /v1/models and /v1/chat/completions for Open WebUI.

resource "kubectl_manifest" "litellm_config" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "litellm-config"
      namespace = "default"
    }
    data = {
      # API key injected via env var — not stored in the ConfigMap
      "config.yaml" = "model_list:\n  - model_name: ${module.ai_foundry.deployment_name}\n    litellm_params:\n      model: azure/${module.ai_foundry.deployment_name}\n      api_base: ${module.ai_foundry.openai_endpoint}\n      api_key: os.environ/AZURE_API_KEY\n      api_version: \"${module.ai_foundry.openai_api_version}\"\n"
    }
  })

  depends_on = [module.aks]
}

resource "kubectl_manifest" "litellm_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "litellm"
      namespace = "default"
    }
    spec = {
      replicas = 1
      selector = { matchLabels = { app = "litellm" } }
      template = {
        metadata = {
          labels = { app = "litellm" }
          annotations = {
            "checksum/config" = sha256("${module.ai_foundry.deployment_name}${module.ai_foundry.openai_endpoint}${module.ai_foundry.openai_api_version}")
          }
        }
        spec = {
          containers = [
            {
              name  = "litellm"
              image = var.litellm_image
              args  = ["--config", "/app/config.yaml", "--port", "4000"]
              ports = [{ containerPort = 4000 }]
              env = [
                {
                  name = "AZURE_API_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name = "azure-openai-secret"
                      key  = "api-key"
                    }
                  }
                }
              ]
              volumeMounts = [
                {
                  name      = "config"
                  mountPath = "/app/config.yaml"
                  subPath   = "config.yaml"
                }
              ]
            }
          ]
          volumes = [
            {
              name      = "config"
              configMap = { name = "litellm-config" }
            }
          ]
          tolerations = [
            {
              key      = "kubernetes.azure.com/scalesetpriority"
              operator = "Equal"
              value    = "spot"
              effect   = "NoSchedule"
            }
          ]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.litellm_config, kubernetes_secret.azure_openai]
}

resource "kubectl_manifest" "litellm_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "litellm"
      namespace = "default"
    }
    spec = {
      selector = { app = "litellm" }
      ports    = [{ port = 4000, targetPort = 4000 }]
      type     = "ClusterIP"
    }
  })

  depends_on = [module.aks]
}

# Open WebUI Helm Release
resource "helm_release" "open_webui" {
  name       = "open-webui"
  repository = "https://helm.openwebui.com/"
  chart      = "open-webui"
  version    = var.open_webui_chart_version
  namespace  = "default"
  timeout    = 600 # 10 minutes

  # Helm values
  values = [
    yamlencode({
      replicaCount = 1

      # LiteLLM proxy exposes a standard OpenAI-compatible /v1 endpoint.
      # It handles Azure's deployment URL format and api-version internally.
      openaiBaseApiUrl = "http://litellm.default.svc.cluster.local:4000/v1"
      openaiApiKey     = "sk-no-key"

      # Disable subcharts not needed for this setup
      ollama = {
        enabled = false
      }
      pipelines = {
        enabled = false
      }
      websocket = {
        enabled = false
      }

      extraEnvVars = [
        {
          name  = "DEFAULT_MODELS"
          value = module.ai_foundry.deployment_name
        },
        {
          name  = "WEBUI_AUTH"
          value = "False"
        },
        {
          name  = "ENABLE_PERSISTENT_CONFIG"
          value = "False"
        }
      ]

      tolerations = [
        {
          key      = "kubernetes.azure.com/scalesetpriority"
          operator = "Equal"
          value    = "spot"
          effect   = "NoSchedule"
        }
      ]

      resources = {
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
        requests = {
          cpu    = "250m"
          memory = "512Mi"
        }
      }

      service = {
        type = "ClusterIP"
        port = 80
      }

      persistence = {
        enabled = false
      }

      ingress = {
        enabled = false
      }

      route = {
        enabled    = true
        apiVersion = "gateway.networking.k8s.io/v1"
        kind       = "HTTPRoute"
        hostnames  = [local.app_fqdn]
        parentRefs = [
          {
            name      = "traefik-gateway"
            namespace = "traefik"
          }
        ]
        httpsRedirect = true
      }
    })
  ]

  depends_on = [
    module.aks,
    kubectl_manifest.traefik_gateway,
    kubectl_manifest.letsencrypt_issuer,
  ]
}

resource "null_resource" "post_deploy" {
  triggers = {
    always_run = timestamp()
  }

  # Merge the new cluster into local kubeconfig
  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${local.resource_group_name} --name ${local.aks_cluster_name} --overwrite-existing"
  }

  # Wait for the app URL to respond (up to 10 minutes)
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for https://${local.app_fqdn} to be ready..."
      for i in $(seq 1 60); do
        if curl -sf --max-time 10 "https://${local.app_fqdn}" > /dev/null 2>&1; then
          echo "App is ready at https://${local.app_fqdn}"
          exit 0
        fi
        echo "  Attempt $i/60 — not ready yet, retrying in 10s..."
        sleep 10
      done
      echo "Warning: app did not respond within 10 minutes. Check certificate and pod status."
      exit 0
    EOT
  }

  depends_on = [helm_release.open_webui, kubectl_manifest.open_webui_certificate]
}
