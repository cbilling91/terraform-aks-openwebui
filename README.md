# Open WebUI on Azure AKS with Azure AI Foundry

A cost-optimized POC deployment of Open WebUI on Azure Kubernetes Service (AKS), integrated with Azure AI Foundry (Azure OpenAI GPT-4) for a production-ready chat interface.

## Overview

This project demonstrates infrastructure as code for deploying a complete AI chat application using:
- **Azure Kubernetes Service (AKS)** - Free tier with spot instances for cost optimization
- **Azure OpenAI Service** - GPT-4 model deployment via Azure AI Foundry
- **Open WebUI** - Modern chat interface for GPT models
- **Terraform** - Infrastructure provisioning and management

### Key Features

- **100% Infrastructure as Code** - Everything deployed via Terraform (including Helm)
- Cost-optimized architecture (~$40-50/month infrastructure)
- Free tier AKS cluster with mixed node pools (system + spot)
- Azure OpenAI GPT-4 integration
- Automated deployment and teardown scripts
- Production-ready Terraform modules
- Comprehensive documentation

## Architecture

```
User (Browser)
    ↓ [HTTP]
Azure Load Balancer (Public IP)
    ↓
Open WebUI (AKS Pod on Spot Instance)
    ↓ [OpenAI-compatible API via HTTPS]
Azure OpenAI Service (GPT-4)
    ↓
GPT-4 Deployment (10K TPM, East US)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed architecture documentation.

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

- Active Azure subscription
- Azure OpenAI access (may require申请 for GPT-4)
- Sufficient quota for Standard_B2s VMs (at least 4 vCPUs)
- Permissions to create resources in your subscription

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to project directory
cd aks-openwebui-project

# Copy and configure Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit terraform.tfvars with your values
# IMPORTANT: Update openai_account_name with a globally unique name
nano terraform/terraform.tfvars
```

### 2. Bootstrap Terraform Backend (One-time)

```bash
# Create Azure Storage for Terraform state
cd scripts
./bootstrap-backend.sh
cd ..
```

This creates an Azure Storage Account for Terraform remote state management.

### 3. Deploy Infrastructure

```bash
# Run automated deployment
cd scripts
./deploy.sh
```

The deployment script will:
1. Validate prerequisites and Azure authentication
2. Run Terraform to provision **everything**:
   - Resource Group
   - Azure OpenAI Service (GPT-4)
   - AKS Cluster (free tier + mixed nodes)
   - Kubernetes Secret (API key)
   - Open WebUI (via Terraform Helm provider)
3. Configure kubectl for AKS access
4. Wait for LoadBalancer IP assignment
5. Display access URL

**Everything is deployed via Terraform** - no manual kubectl or helm commands needed!

Deployment takes approximately **10-15 minutes**.

### 4. Access Open WebUI

Once deployment completes, access the chat interface at the provided URL:

```
http://<EXTERNAL-IP>
```

**First-time setup:**
1. Create an account (first user becomes admin)
2. Start chatting with GPT-4!

### 5. Teardown (After Demo)

```bash
cd scripts
./destroy.sh
```

This destroys all POC resources cleanly.

## Project Structure

```
aks-openwebui-project/
├── README.md                          # This file
├── ARCHITECTURE.md                     # Architecture documentation
├── terraform/                          # Infrastructure as Code
│   ├── main.tf                        # Root module
│   ├── variables.tf                   # Input variables
│   ├── outputs.tf                     # Output values
│   ├── providers.tf                   # Azure provider config
│   ├── backend.tf                     # Terraform state backend
│   ├── terraform.tfvars.example       # Example variables
│   └── modules/                       # Terraform modules
│       ├── resource-group/            # Resource group module
│       ├── ai-foundry/                # Azure OpenAI module
│       └── aks/                       # AKS cluster module
├── kubernetes/                         # Kubernetes reference
│   └── secrets.yaml.example           # Secret template (reference only)
│                                      # Note: All K8s resources deployed via Terraform
├── scripts/                            # Automation scripts
│   ├── bootstrap-backend.sh           # Setup Terraform backend
│   ├── deploy.sh                      # Full deployment
│   ├── destroy.sh                     # Complete teardown
│   ├── setup-kubeconfig.sh            # Configure kubectl
│   └── test-connection.sh             # Test Azure OpenAI
└── docs/                               # Additional documentation
    ├── deployment-guide.md
    ├── cost-analysis.md
    └── troubleshooting.md
```

## Cost Analysis

**Estimated Monthly Cost: $40-50** (excluding GPT-4 token usage)

| Component | Configuration | Monthly Cost |
|-----------|--------------|--------------|
| AKS Control Plane | Free tier | $0 |
| System Node Pool | 1x Standard_B2s (regular) | ~$30-35 |
| User Node Pool | 1x Standard_B2s (spot) | ~$3-5 |
| Azure Storage | Terraform state | ~$1-2 |
| **Total Infrastructure** | | **~$40-45** |
| GPT-4 Token Usage | Pay-per-use (10K TPM limit) | Variable (~$5-10 for demo) |

See [docs/cost-analysis.md](docs/cost-analysis.md) for detailed cost breakdown and optimization strategies.

## Useful Commands

### Terraform

```bash
# Initialize Terraform
cd terraform && terraform init

# Plan infrastructure changes (includes Helm release)
terraform plan

# Apply changes (deploys everything including Open WebUI)
terraform apply

# Destroy infrastructure (removes everything cleanly)
terraform destroy

# Show outputs
terraform output

# View Helm release status
terraform state show helm_release.open_webui
```

### Kubernetes

```bash
# Get AKS credentials
az aks get-credentials --resource-group <rg-name> --name <cluster-name>

# View cluster nodes
kubectl get nodes

# View pods
kubectl get pods

# View services
kubectl get svc

# View logs
kubectl logs -l app=open-webui

# View Open WebUI service details
kubectl describe svc open-webui
```

### Helper Scripts

```bash
# Configure kubectl for AKS
./scripts/setup-kubeconfig.sh

# Test Azure OpenAI connectivity
./scripts/test-connection.sh
```

## Troubleshooting

### Common Issues

**Terraform State Locking**
```bash
# If state lock persists after error, manually unlock:
cd terraform
terraform force-unlock <LOCK_ID>
```

**LoadBalancer IP Not Assigning**
```bash
# Check service status:
kubectl describe svc open-webui

# Check Azure LoadBalancer provisioning:
az network lb list --resource-group <node-resource-group>
```

**Azure OpenAI Connection Errors**
```bash
# Test connectivity:
./scripts/test-connection.sh

# Verify API key:
kubectl get secret azure-openai-secret -o jsonpath='{.data.api-key}' | base64 -d
```

See [docs/troubleshooting.md](docs/troubleshooting.md) for more solutions.

## Documentation

- [Architecture Overview](ARCHITECTURE.md) - Detailed architecture, components, and design decisions
- [Deployment Guide](docs/deployment-guide.md) - Step-by-step deployment instructions
- [Cost Analysis](docs/cost-analysis.md) - Detailed cost breakdown and optimization
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## Security Considerations

This POC prioritizes simplicity and cost optimization. For production deployments, consider:

- Private AKS cluster (no public API endpoint)
- Azure Private Link for Azure OpenAI
- Managed identities instead of API keys
- Network policies and NSG rules
- HTTPS/TLS with custom domain and certificate
- Azure Key Vault for secret management
- RBAC and pod security policies
- Enable AKS monitoring and logging

## Demo Presentation Workflow

### Preparation

1. **One-time backend setup:**
   ```bash
   ./scripts/bootstrap-backend.sh
   ```

2. **Configure variables:**
   - Edit `terraform/terraform.tfvars` with unique values
   - Ensure Azure OpenAI access is approved

### Live Demo

1. **Start from clean state:**
   ```bash
   ./scripts/destroy.sh  # If previous deployment exists
   ```

2. **Deploy full stack:**
   ```bash
   ./scripts/deploy.sh
   ```
   *Deployment time: 10-15 minutes*

3. **Access Open WebUI:**
   - Navigate to displayed URL
   - Create account and send test message
   - Demonstrate GPT-4 response

4. **Discuss architecture:**
   - Show Terraform code structure
   - Explain cost optimization (free tier, spot instances)
   - Review Azure Portal resources

5. **Teardown:**
   ```bash
   ./scripts/destroy.sh
   ```

## License

This project is provided as-is for educational and demonstration purposes.

## Acknowledgments

- [Open WebUI](https://github.com/open-webui/open-webui) - Modern chat interface for LLMs
- [Azure AI Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/) - Azure OpenAI Service
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) - Infrastructure provisioning

---

**Infrastructure Engineer Case Study - aks-openwebui POC**
