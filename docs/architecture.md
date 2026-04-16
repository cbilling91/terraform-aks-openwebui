# Architecture

## Overview

This project deploys a complete AI chat stack on Azure using Terraform as the single deployment mechanism — no manual `kubectl` or `helm` commands required.

**Stack:**
- **Traefik** — Gateway API-based ingress controller with static public IP
- **cert-manager** — Automated TLS certificate provisioning via Let's Encrypt
- **LiteLLM** — OpenAI-compatible proxy that fronts Azure OpenAI
- **Open WebUI** — Chat interface, routes traffic through LiteLLM
- **Azure OpenAI (AI Foundry)** — GPT model backend

---

## Traffic Flow

```
User (Browser)
    │ HTTPS — valid TLS cert (Let's Encrypt)
    ↓
Azure Static Public IP
    │
    ↓
Traefik (Gateway API)
    │ HTTPRoute → open-webui service (ClusterIP :80)
    ↓
Open WebUI Pod
    │ OpenAI-compatible API → http://litellm-service:4000
    ↓
LiteLLM Pod
    │ HTTPS Azure OpenAI API
    ↓
Azure OpenAI (AI Foundry)
    └── GPT model deployment
```

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          End Users                              │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS (Let's Encrypt TLS)
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│            Static Public IP (Azure DNS FQDN)                    │
│     <project_name>.<location>.cloudapp.azure.com                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│              Azure Kubernetes Service (AKS)                     │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  traefik namespace                                       │   │
│  │  - Traefik Deployment (Gateway API controller)           │   │
│  │  - GatewayClass: traefik                                 │   │
│  │  - Gateway: traefik-gateway (bound to static public IP)  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  cert-manager namespace                                  │   │
│  │  - cert-manager Deployment                               │   │
│  │  - ClusterIssuer: letsencrypt (HTTP-01 challenge)        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  default namespace                                       │   │
│  │                                                          │   │
│  │  LiteLLM Pod          Open WebUI Pod                    │   │
│  │  - Port: 4000          - Port: 8080                     │   │
│  │  - ConfigMap: model    - Service: ClusterIP :80         │   │
│  │    routing config      - HTTPRoute → Gateway            │   │
│  │  - Secret: Azure       - Certificate (TLS)              │   │
│  │    OpenAI API key                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Node Pools:                                                     │
│  - System Pool: 1x Standard_B4ms (regular) — system pods       │
│  - User Pool:   1x Standard_D2s_v3 (regular or spot) — workload│
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│              Azure OpenAI (AI Foundry)                          │
│  - Model: gpt-4o (configurable)                                 │
│  - Capacity: 10K TPM                                            │
│  - API Version: 2024-12-01-preview                              │
│  - Auth: API key (stored in Kubernetes secret)                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Terraform Module Structure

```
terraform-aks-openwebui-project/
├── main.tf              # locals + module.resource_group + random_string
├── ai-foundry.tf        # module.ai_foundry (Azure OpenAI)
├── kubernetes.tf        # module.aks + all Helm/kubectl resources
├── variables.tf         # all input variables
├── outputs.tf           # app_url, cluster name, RG name, etc.
├── providers.tf         # azurerm, kubernetes, helm, kubectl provider configs
├── versions.tf          # required_providers (incl. gavinbunney/kubectl)
└── modules/
    ├── resource-group/  # azurerm_resource_group
    ├── aks/             # azurerm_kubernetes_cluster + node pools
    └── ai-foundry/      # azurerm_cognitive_account + deployment
```

### Why `gavinbunney/kubectl`

The standard `hashicorp/kubernetes` provider struggles with CRD-based resources (like `GatewayClass`, `Gateway`, `ClusterIssuer`) because it tries to validate the schema at plan time — before those CRDs exist. The `gavinbunney/kubectl` provider applies manifests more loosely (like `kubectl apply -f`), which correctly handles CRDs installed by Helm charts.

### Provider Bootstrap

The kubernetes/helm/kubectl providers need the AKS cluster endpoint and certificates to connect, but those only exist after the cluster is created. This is handled with `try(..., "")` in `providers.tf`:

```hcl
provider "kubernetes" {
  host = try(module.aks.cluster_endpoint, "")
  ...
}
```

During `terraform plan`, `module.aks.cluster_endpoint` is unknown so `try()` returns `""`. During `terraform apply`, Terraform creates the AKS cluster first (via explicit `depends_on`), then re-evaluates provider configuration with real credentials before creating any Kubernetes resources.

---

## Components

### Traefik

- Deployed via Helm with Gateway API support enabled
- Loads static public IP via `service.spec.loadBalancerIP`
- Acts as the single ingress point; Open WebUI is exposed via an HTTPRoute

### cert-manager

- Deployed via Helm
- ClusterIssuer configured for Let's Encrypt HTTP-01 challenge
- Certificate resource requests a TLS cert for the Azure DNS FQDN
- Cert auto-renewed before expiry

### LiteLLM

- Deployed as a Kubernetes Deployment + Service (ClusterIP)
- ConfigMap holds model routing configuration (maps requests to Azure OpenAI)
- Kubernetes Secret holds the Azure OpenAI API key
- Open WebUI points to LiteLLM's OpenAI-compatible endpoint

### Open WebUI

- Deployed via Helm chart
- Service type: ClusterIP (not LoadBalancer — traffic comes in via Traefik)
- HTTPRoute routes traffic from the Traefik Gateway to the Open WebUI service
- Persistence disabled (stateless POC)

### Azure OpenAI (AI Foundry)

- `azurerm_cognitive_account` — OpenAI service
- `azurerm_cognitive_deployment` — model deployment (default: gpt-4o)
- API key stored as Kubernetes Secret, consumed by LiteLLM

---

## Design Decisions

### LiteLLM as Proxy

Open WebUI supports Azure OpenAI natively, but routing it through LiteLLM provides an OpenAI-compatible API abstraction layer. This makes it easier to swap models or providers later without reconfiguring Open WebUI.

### Gateway API vs Ingress

Traefik supports both the traditional Ingress API and the newer Gateway API. Gateway API is used here because it provides better separation between infrastructure (Gateway) and application (HTTPRoute) concerns, and is the direction the Kubernetes ecosystem is moving.

### Static Public IP

The public IP is created as an Azure resource (in the AKS node resource group where the cluster identity has permissions) and bound to Traefik. This ensures the DNS FQDN is stable and doesn't change across Traefik restarts.

### Cost Optimization

| Decision | Saving |
|----------|--------|
| Free tier AKS | $0 control plane |
| Optional spot instances (user pool) | ~90% on user node |
| Minimal VM sizes | Right-sized for POC |
| No persistent storage | Saves disk costs |
| 10K TPM cap on Azure OpenAI | Prevents runaway token costs |

---

## Security

**Current POC configuration:**
- Public AKS API endpoint
- TLS termination at Traefik (HTTPS to clients)
- API key authentication to Azure OpenAI
- No network policies

**Production recommendations:**
1. Private AKS cluster (no public API endpoint)
2. Azure Private Link for Azure OpenAI
3. Workload identity / managed identity instead of API keys
4. Network policies for pod-to-pod traffic control
5. Azure Key Vault for secret management
6. RBAC and pod security standards
7. Azure Monitor / Log Analytics for observability
