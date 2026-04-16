# Open WebUI on Azure AKS with Azure AI Foundry

A cost-optimized POC deployment of Open WebUI on Azure Kubernetes Service (AKS), integrated with Azure AI Foundry (Azure OpenAI GPT-4) for a production-ready chat interface.

## Overview

This project demonstrates infrastructure as code for deploying a complete AI chat application using:
- **Azure Kubernetes Service (AKS)** - Free tier with spot instances for cost optimization
- **Azure OpenAI Service** - GPT-4 model deployment via Azure AI Foundry
- **Open WebUI** - Modern chat interface for GPT models
- **Terraform** - Infrastructure provisioning and management

### Key Features

- **100% Infrastructure as Code** — everything deployed via Terraform (including Helm and kubectl manifests)
- HTTPS with Let's Encrypt TLS via cert-manager (no manual certificate management)
- Traefik Gateway API ingress controller
- LiteLLM proxy for OpenAI-compatible API abstraction
- Free tier AKS cluster with optional spot instances for cost savings
- Azure OpenAI (AI Foundry) integration — configurable model
- Production-ready Terraform modules

## Architecture

```
User (Browser)
    ↓ [HTTPS — Let's Encrypt TLS]
Static Public IP / Azure DNS FQDN
    ↓
Traefik (Gateway API)
    ↓ [HTTPRoute]
Open WebUI Pod
    ↓ [OpenAI-compatible API]
LiteLLM Pod
    ↓ [HTTPS]
Azure OpenAI (AI Foundry) — gpt-4o
```

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation.

## Prerequisites

Before deploying, ensure you have the following installed and configured:

### Required Tools

- **Azure CLI** (v2.50+)
  ```bash
  az --version
  az login
  ```

- **Terraform** (v1.5+)
  ```bash
  terraform --version
  ```

- **kubectl** (v1.27+)
  ```bash
  kubectl version --client
  ```

- **Helm** (v3.12+)
  ```bash
  helm version
  ```

### Azure Requirements

- Active Azure subscription with permissions to create resources
- Azure OpenAI access approved (apply at https://aka.ms/oai/access if needed)
- Sufficient vCPU quota for `Standard_D2s_v3` (default; 2 vCPUs for user pool)
- A Let's Encrypt-compatible email address for `letsencrypt_email`

## Quick Start

### 1. Clone and Configure

```bash
git clone <repository-url>
cd terraform-aks-openwebui-project

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set project_name, location, letsencrypt_email
```

### 2. Deploy

```bash
terraform init
terraform apply
```

Terraform provisions everything: AKS cluster, Traefik, cert-manager, LiteLLM, Open WebUI, and a Let's Encrypt TLS certificate. Deployment takes approximately **15-20 minutes**.

### 3. Access Open WebUI

```
https://<project_name>.<location>.cloudapp.azure.com
```

The URL is also printed as `app_url` in the Terraform output.

### 4. Teardown

```bash
terraform destroy
```

## Project Structure

```
terraform-aks-openwebui-project/
├── main.tf                    # locals, resource group, random suffix
├── ai-foundry.tf              # Azure OpenAI (AI Foundry) module
├── kubernetes.tf              # AKS cluster + all Helm/kubectl resources
├── variables.tf               # Input variables
├── outputs.tf                 # app_url, cluster name, etc.
├── providers.tf               # azurerm, kubernetes, helm, kubectl providers
├── versions.tf                # required_providers
├── terraform.tfvars.example   # Example variable values
├── modules/
│   ├── resource-group/        # azurerm_resource_group
│   ├── aks/                   # AKS cluster + node pools
│   └── ai-foundry/            # Azure OpenAI service + deployment
├── scripts/                   # Helper scripts (kubeconfig, connection test)
└── docs/
    ├── architecture.md
    ├── deployment-guide.md
    ├── cost-analysis.md
    └── troubleshooting.md
```

## Cost Analysis

| Component | Configuration | Monthly Cost |
|-----------|--------------|--------------|
| AKS Control Plane | Free tier | $0 |
| System Node Pool | 1x Standard_B4ms (regular) | ~$140 |
| User Node Pool | 1x Standard_D2s_v3 (spot) | ~$7 |
| Static Public IP | Standard | ~$3 |
| Azure OpenAI | Pay-per-token (10K TPM cap) | Variable |

Enable `spot_instances = true` in `terraform.tfvars` to use spot pricing on the user node pool (~90% savings, subject to eviction).

See [docs/cost-analysis.md](docs/cost-analysis.md) for detailed breakdown and optimization options.

## Useful Commands

```bash
# Terraform
terraform init
terraform plan
terraform apply
terraform destroy
terraform output

# Get AKS credentials
az aks get-credentials --resource-group rg-<project_name>-<environment> --name <project_name>

# Check pods across key namespaces
kubectl get pods -A | grep -E "traefik|cert-manager|litellm|open-webui"

# Check TLS certificate status
kubectl get certificate -A

# Open WebUI logs
kubectl logs -f -l app.kubernetes.io/name=open-webui

# LiteLLM logs
kubectl logs -f -l app=litellm

# Helper scripts
./scripts/setup-kubeconfig.sh     # configure kubectl
./scripts/test-connection.sh      # test Azure OpenAI connectivity
```

## Troubleshooting

**TLS certificate not ready** — cert-manager uses HTTP-01 challenge. Check that Traefik's public IP is assigned and DNS is resolving, then check `kubectl describe certificate -A`.

**`hashicorp/kubectl` provider not found** — Run `terraform init` from the project root. The correct provider (`gavinbunney/kubectl`) is declared in `versions.tf`.

**"No Models Available" in Open WebUI** — LiteLLM is the intermediary. Check `kubectl logs -l app=litellm` for Azure OpenAI connectivity errors.

**Spot node evicted** — AKS replaces it automatically within a few minutes. For demos requiring guaranteed uptime, set `spot_instances = false`.

See [docs/troubleshooting.md](docs/troubleshooting.md) for detailed solutions.

## Documentation

- [Architecture](docs/architecture.md) — components, traffic flow, design decisions
- [Deployment Guide](docs/deployment-guide.md) — step-by-step deployment instructions
- [Cost Analysis](docs/cost-analysis.md) — cost breakdown and optimization options
- [Troubleshooting](docs/troubleshooting.md) — common issues and solutions

## Security Considerations

This POC prioritizes simplicity. For production deployments, consider:

- Private AKS cluster (no public API endpoint)
- Azure Private Link for Azure OpenAI
- Workload identity instead of API keys
- Network policies for pod-to-pod traffic
- Azure Key Vault for secret management
- RBAC and pod security standards
- Azure Monitor / Log Analytics for observability

## Acknowledgments

- [Open WebUI](https://github.com/open-webui/open-webui)
- [LiteLLM](https://github.com/BerriAI/litellm)
- [Traefik](https://traefik.io)
- [cert-manager](https://cert-manager.io)
- [Azure AI Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/)
