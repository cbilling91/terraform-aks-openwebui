locals {
  app_fqdn = "${var.app_dns_label}.${var.location}.cloudapp.azure.com"
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

  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Azure AI Foundry (OpenAI) Module
module "ai_foundry" {
  source = "./modules/ai-foundry"

  openai_account_name = "${var.openai_account_name}-${random_string.unique_suffix.result}"
  location            = var.location
  resource_group_name = module.resource_group.resource_group_name

  deployment_name = "${var.openai_model_name}-deployment"
  model_name      = var.openai_model_name
  model_version   = var.openai_model_version
  capacity        = 10 # 10K TPM for cost control

  tags = var.tags

  depends_on = [module.resource_group]
}

# AKS Cluster Module
module "aks" {
  source = "./modules/aks"

  cluster_name        = var.aks_cluster_name
  location            = var.location
  resource_group_name = module.resource_group.resource_group_name
  dns_prefix          = var.aks_dns_prefix

  # Kubernetes version
  kubernetes_version = "1.34.4"

  # System node pool (regular nodes)
  system_node_count   = 1
  system_node_vm_size = "Standard_D2s_v3"

  # User node pool (spot instances)
  user_node_count   = 1
  user_node_vm_size = "Standard_D2s_v3"

  tags = var.tags

  depends_on = [module.resource_group]
}

# Kubernetes Gateway API standard CRDs (required by Traefik Gateway API support)
# Fetched from the official release and applied via the kubectl provider, which
# does not validate CRD schemas at plan time (unlike kubernetes_manifest).
data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml"
}

data "kubectl_file_documents" "gateway_api_crds" {
  content = data.http.gateway_api_crds.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each  = data.kubectl_file_documents.gateway_api_crds.manifests
  yaml_body = each.value

  depends_on = [module.aks]
}

# Static public IP for Traefik — placed in AKS node resource group where the
# cluster identity has automatic permissions
resource "azurerm_public_ip" "ingress" {
  name                = "pip-${var.project_name}-ingress"
  location            = var.location
  resource_group_name = module.aks.node_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.app_dns_label
  tags                = var.tags

  depends_on = [module.aks]
}

# Traefik with Gateway API support enabled
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://helm.traefik.io/traefik"
  chart            = "traefik"
  namespace        = "traefik"
  create_namespace = true
  timeout          = 300

  values = [
    yamlencode({
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

      tolerations = [
        {
          key      = "kubernetes.azure.com/scalesetpriority"
          operator = "Equal"
          value    = "spot"
          effect   = "NoSchedule"
        }
      ]

      nodeSelector = {
        "workload-type" = "spot"
      }
    })
  ]

  depends_on = [module.aks, azurerm_public_ip.ingress, kubectl_manifest.gateway_api_crds]
}

# cert-manager for TLS certificate lifecycle management
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.16.3"
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

      nodeSelector = {
        "workload-type" = "spot"
      }

      webhook = {
        tolerations = [
          {
            key      = "kubernetes.azure.com/scalesetpriority"
            operator = "Equal"
            value    = "spot"
            effect   = "NoSchedule"
          }
        ]
        nodeSelector = {
          "workload-type" = "spot"
        }
      }

      cainjector = {
        tolerations = [
          {
            key      = "kubernetes.azure.com/scalesetpriority"
            operator = "Equal"
            value    = "spot"
            effect   = "NoSchedule"
          }
        ]
        nodeSelector = {
          "workload-type" = "spot"
        }
      }

      startupapicheck = {
        tolerations = [
          {
            key      = "kubernetes.azure.com/scalesetpriority"
            operator = "Equal"
            value    = "spot"
            effect   = "NoSchedule"
          }
        ]
        nodeSelector = {
          "workload-type" = "spot"
        }
      }
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
                podTemplate = {
                  spec = {
                    tolerations = [
                      {
                        key      = "kubernetes.azure.com/scalesetpriority"
                        operator = "Equal"
                        value    = "spot"
                        effect   = "NoSchedule"
                      }
                    ]
                    nodeSelector = {
                      "workload-type" = "spot"
                    }
                  }
                }
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

  depends_on = [helm_release.traefik, kubectl_manifest.gateway_api_crds]
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
        metadata = { labels = { app = "litellm" } }
        spec = {
          containers = [
            {
              name  = "litellm"
              image = "ghcr.io/berriai/litellm:main-stable"
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
          nodeSelector = { "workload-type" = "spot" }
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
  namespace  = "default"
  timeout    = 600 # 10 minutes

  # Helm values
  values = [
    yamlencode({
      replicaCount = 1

      # LiteLLM proxy handles Azure OpenAI URL format and api-version internally.
      # Open WebUI talks to LiteLLM as a standard OpenAI-compatible endpoint.
      openaiBaseApiUrl = "http://litellm.default.svc.cluster.local:4000/v1"
      openaiApiKey     = "sk-no-key" # LiteLLM has no master_key — any value works

      # Disable subcharts not needed for this setup
      ollama = {
        enabled = false
      }
      pipelines = {
        enabled = false
      }
      # Disable websocket: the chart has no websocket.tolerations value, so the
      # websocket pod cannot be given the spot toleration and would fail to schedule
      websocket = {
        enabled = false
      }

      extraEnvVars = [
        {
          name  = "DEFAULT_MODELS"
          value = module.ai_foundry.deployment_name
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

      nodeSelector = {
        "workload-type" = "spot"
      }

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
