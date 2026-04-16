# Deployment Guide

Step-by-step guide for deploying Open WebUI on AKS with Azure OpenAI.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Deployment](#deployment)
4. [Verification](#verification)
5. [Post-Deployment](#post-deployment)
6. [Teardown](#teardown)

---

## Prerequisites

### Required Tools

#### Azure CLI (v2.50+)

```bash
# Install (macOS)
brew install azure-cli

# Install (Windows)
choco install azure-cli

# Install (Linux)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

az --version
az login
az account set --subscription "<subscription-id>"
```

#### Terraform (v1.5+)

```bash
# Install (macOS)
brew tap hashicorp/tap && brew install hashicorp/tap/terraform

# Install (Windows)
choco install terraform

terraform --version
```

#### kubectl (v1.27+)

```bash
# Install (macOS)
brew install kubectl

# Install (Windows)
choco install kubernetes-cli

kubectl version --client
```

### Azure Requirements

- Active Azure subscription with permission to create resources
- Azure OpenAI access approved for your subscription (apply at https://aka.ms/oai/access if needed)
- Sufficient vCPU quota for your chosen VM size (default `Standard_D2s_v3` requires 4 vCPUs)
- A domain or acceptance of the auto-assigned Azure DNS FQDN (`<project_name>.<location>.cloudapp.azure.com`)

---

## Pre-Deployment Checklist

### 1. Clone Repository

```bash
git clone <repository-url>
cd terraform-aks-openwebui-project
```

### 2. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
project_name      = "my-openwebui"       # Used for all resource naming and DNS label
environment       = "demo"
location          = "eastus"
letsencrypt_email = "you@example.com"    # Required for TLS certificate registration

tags = {
  Project     = "AKS-OpenWebUI"
  Environment = "Demo"
  ManagedBy   = "Terraform"
}
```

**Required:** `project_name` becomes the public DNS label — it must be unique within the Azure region. The app will be accessible at `https://<project_name>.<location>.cloudapp.azure.com`.

**Optional overrides** (defaults are set in `variables.tf`):

```hcl
openai_model_name          = "gpt-4o"           # Azure OpenAI model to deploy
spot_instances             = false               # true for ~90% cost savings (subject to eviction)
user_node_vm_size          = "Standard_D2s_v3"
user_node_count            = 1
kubernetes_version         = "1.34.4"
traefik_chart_version      = "39.0.7"
cert_manager_chart_version = "v1.20.1"
open_webui_chart_version   = "13.3.1"
```

### 3. Verify Authentication

```bash
az account show
az account list --output table
```

---

## Deployment

Everything — AKS cluster, Traefik ingress, cert-manager, LiteLLM, Open WebUI, TLS certificate — is deployed in a single `terraform apply`.

```bash
# Initialize providers and modules
terraform init

# Preview what will be created
terraform plan

# Deploy (takes 15-20 minutes)
terraform apply
```

When prompted, type `yes` to confirm.

### What Gets Deployed

**Phase 1 — Azure infrastructure** (~5 min):
- Resource group
- AKS cluster with system + user node pools
- Azure OpenAI (AI Foundry) with model deployment
- Static public IP in the AKS node resource group

**Phase 2 — Kubernetes platform** (~5 min):
- Traefik (ingress/gateway controller) with Gateway API
- cert-manager with Let's Encrypt ClusterIssuer
- Traefik GatewayClass and Gateway bound to the static IP

**Phase 3 — Application** (~5 min):
- TLS certificate (issued by Let's Encrypt via cert-manager)
- LiteLLM proxy deployment (fronts Azure OpenAI with OpenAI-compatible API)
- Open WebUI Helm release
- HTTPRoute wiring Open WebUI through the Traefik Gateway

**Post-deploy:**
- `az aks get-credentials` updates your local kubeconfig automatically
- Waits up to 10 minutes for `https://<fqdn>` to respond

### Deployment Output

```
Apply complete! Resources: N added, 0 changed, 0 destroyed.

Outputs:

app_url                = "https://my-openwebui.eastus.cloudapp.azure.com"
aks_cluster_name       = "my-openwebui"
resource_group_name    = "rg-my-openwebui-demo"
openai_deployment_name = "gpt-4o"
```

---

## Verification

### Azure Resources

```bash
# List everything in the resource group
az resource list --resource-group rg-<project_name>-<environment> --output table

# Check AKS cluster
az aks show --name <project_name> --resource-group rg-<project_name>-<environment> --query "powerState"
```

### Kubernetes Resources

```bash
# Get credentials (if not already set by post-deploy)
az aks get-credentials --resource-group rg-<project_name>-<environment> --name <project_name>

# Check nodes
kubectl get nodes

# Check all pods across relevant namespaces
kubectl get pods -A | grep -E "traefik|cert-manager|litellm|open-webui"

# Check TLS certificate status
kubectl get certificate -A

# Check Traefik gateway
kubectl get gateway -A
```

### Access the App

1. Open `https://<project_name>.<location>.cloudapp.azure.com` in your browser
2. You should see the Open WebUI login page with a valid TLS certificate

If the certificate is still provisioning (can take 1-2 minutes after deploy), you may see a browser TLS warning briefly. Wait and refresh.

---

## Post-Deployment

### First-Time Setup

1. **Create an account** — first user becomes admin
2. **Model is pre-configured** — LiteLLM routes requests to Azure OpenAI automatically; no manual model setup needed
3. **Start chatting**

### Useful Commands

```bash
# View all Terraform outputs
terraform output

# Get kubeconfig
az aks get-credentials --resource-group rg-<project_name>-<environment> --name <project_name>

# Watch pod status
kubectl get pods -w

# Open WebUI logs
kubectl logs -f -l app.kubernetes.io/name=open-webui

# LiteLLM logs
kubectl logs -f -l app=litellm

# Traefik logs
kubectl logs -f -n traefik -l app.kubernetes.io/name=traefik

# Check certificate
kubectl describe certificate -A
```

### Redeploying a Component

```bash
# Force Helm release to redeploy (e.g., after config change)
terraform apply -replace='helm_release.open_webui'

# Or taint a specific resource
terraform taint helm_release.open_webui
terraform apply
```

---

## Teardown

```bash
terraform destroy
```

Type `yes` to confirm. This removes all resources including the AKS cluster, Azure OpenAI service, and the resource group.

**Note:** The static public IP is in the AKS node resource group (auto-created by AKS) and is destroyed automatically along with the cluster.

To verify deletion:

```bash
az group show --name rg-<project_name>-<environment>
# Should return: ResourceGroupNotFound
```

---

## See Also

- [architecture.md](architecture.md) — architecture overview and design decisions
- [cost-analysis.md](cost-analysis.md) — cost breakdown and optimization
- [troubleshooting.md](troubleshooting.md) — common issues and solutions
