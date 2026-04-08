# Deployment Guide

Comprehensive step-by-step guide for deploying Open WebUI on AKS with Azure OpenAI.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [One-Time Backend Setup](#one-time-backend-setup)
4. [Main Deployment](#main-deployment)
5. [Verification](#verification)
6. [Post-Deployment](#post-deployment)
7. [Teardown](#teardown)
8. [Manual Deployment](#manual-deployment-without-scripts)

---

## Prerequisites

### Required Tools

Install and verify the following tools before proceeding:

#### 1. Azure CLI (v2.50+)

```bash
# Install (macOS)
brew install azure-cli

# Install (Windows)
choco install azure-cli

# Install (Linux)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Verify installation
az --version

# Login to Azure
az login

# Set subscription (if you have multiple)
az account list --output table
az account set --subscription "<subscription-id>"
```

#### 2. Terraform (v1.5+)

```bash
# Install (macOS)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Install (Windows)
choco install terraform

# Install (Linux)
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Verify installation
terraform --version
```

#### 3. kubectl (v1.27+)

```bash
# Install (macOS)
brew install kubectl

# Install (Windows)
choco install kubernetes-cli

# Install (Linux)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify installation
kubectl version --client
```

#### 4. Helm (v3.12+)

```bash
# Install (macOS)
brew install helm

# Install (Windows)
choco install kubernetes-helm

# Install (Linux)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

### Azure Requirements

#### 1. Azure Subscription Access

Verify you have an active Azure subscription:

```bash
az account show
```

#### 2. Azure OpenAI Access

Azure OpenAI (especially GPT-4) requires申请 access:

1. Navigate to: https://aka.ms/oai/access
2. Fill out the申请 form
3. Wait for approval (can take几 days)
4. Verify access:
   ```bash
   az cognitiveservices account list-models \
     --resource-group <test-rg> \
     --name <test-cognitive-account>
   ```

#### 3. Resource Quotas

Check your subscription has sufficient quota:

```bash
# Check quota for Standard_B2s VMs in East US
az vm list-usage --location eastus --output table | grep StandardBSFamily
```

You need at least **4 vCPUs** available for Standard_B2s (2 VMs × 2 vCPUs each).

If quota is insufficient:
1. Azure Portal → Subscriptions → Usage + quotas
2. Request increase for "Standard BSv2 Family vCPUs"
3. Wait for approval

---

## Pre-Deployment Checklist

Before running deployment scripts, complete the following:

### 1. Clone Repository

```bash
cd ~/projects
git clone <repository-url>
cd uniqueai-project
```

### 2. Configure Variables

Copy the example variables file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

```hcl
project_name        = "uniqueai-poc"
environment         = "demo"
location            = "eastus"
resource_group_name = "rg-uniqueai-poc-demo"

# IMPORTANT: Must be globally unique!
# Replace <unique-id> with your initials + random numbers
# Example: openai-uniqueai-jd12345
openai_account_name = "openai-uniqueai-<unique-id>"

aks_cluster_name = "aks-uniqueai-poc"
aks_dns_prefix   = "uniqueai-poc"

tags = {
  Project     = "UniqueAI-POC"
  Environment = "Demo"
  ManagedBy   = "Terraform"
  Purpose     = "CaseStudy"
  Owner       = "YourName"
}
```

**Critical:** The `openai_account_name` must be globally unique across all Azure subscriptions.

### 3. Verify Authentication

```bash
# Ensure you're logged into Azure
az account show

# If not logged in:
az login

# Verify correct subscription is selected
az account list --output table
```

---

## One-Time Backend Setup

This step creates Azure Storage for Terraform state management. **Run only once per project.**

### Automated Setup (Recommended)

```bash
cd scripts
./bootstrap-backend.sh
```

The script will:
1. ✅ Validate Azure authentication
2. ✅ Create resource group: `rg-terraform-state`
3. ✅ Create storage account: `tfstate<unique-id>`
4. ✅ Enable blob versioning for state protection
5. ✅ Create container: `tfstate`
6. ✅ Update `terraform/backend.tf` automatically

**Output example:**

```
========================================
Backend Configuration Complete!
========================================

Add the following to terraform/backend.tf:

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstateabcd1234"
    container_name       = "tfstate"
    key                  = "uniqueai-poc.tfstate"
  }
}

✅ backend.tf updated
✅ Bootstrap complete!
```

### Manual Setup (Alternative)

If the script fails, create manually:

```bash
# Variables
RG_NAME="rg-terraform-state"
LOCATION="eastus"
STORAGE_NAME="tfstate$(openssl rand -hex 4)"
CONTAINER_NAME="tfstate"

# Create resource group
az group create --name $RG_NAME --location $LOCATION

# Create storage account
az storage account create \
  --name $STORAGE_NAME \
  --resource-group $RG_NAME \
  --location $LOCATION \
  --sku Standard_LRS \
  --encryption-services blob

# Get storage key
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group $RG_NAME \
  --account-name $STORAGE_NAME \
  --query '[0].value' -o tsv)

# Create container
az storage container create \
  --name $CONTAINER_NAME \
  --account-name $STORAGE_NAME \
  --account-key $ACCOUNT_KEY

# Update terraform/backend.tf with these values
```

### Verify Backend Setup

```bash
# Check if storage account exists
az storage account show \
  --name <storage-account-name> \
  --resource-group rg-terraform-state
```

---

## Main Deployment

### Automated Deployment (Recommended)

Run the automated deployment script:

```bash
cd scripts
./deploy.sh
```

### Deployment Phases

The script executes the following phases automatically:

#### **Phase 1: Terraform Infrastructure** (5-7 minutes)

The script will:
1. Initialize Terraform (download providers)
2. Validate configuration
3. Create execution plan
4. **Prompt for confirmation** ⚠️
5. Apply infrastructure changes

**Expected output:**

```
========================================
Phase 1: Terraform Infrastructure
========================================

Initializing Terraform...
✅ Terraform initialized

Validating Terraform configuration...
✅ Configuration valid

Planning infrastructure changes...
✅ Plan created

This will create:
  - Resource Group
  - Azure OpenAI (GPT-4)
  - AKS Cluster (Free tier with mixed node pools)

Continue with deployment? (yes/no):
```

Type **`yes`** and press Enter.

**Resources created:**
- Resource Group: `rg-uniqueai-poc-demo`
- Azure Cognitive Services (OpenAI): `openai-uniqueai-<unique-id>`
- GPT-4 Deployment: `gpt-4-deployment`
- AKS Cluster: `aks-uniqueai-poc`
  - System Node Pool: 1x Standard_B2s (regular)
  - User Node Pool: 1x Standard_B2s (spot)

#### **Phase 2: AKS Configuration** (1-2 minutes)

The script will:
1. Retrieve AKS credentials
2. Configure kubectl context
3. Verify cluster access
4. Create Kubernetes secret for Azure OpenAI API key

**Expected output:**

```
========================================
Phase 2: AKS Configuration
========================================

Configuring kubectl for AKS...
✅ kubectl configured

Verifying cluster access...
NAME                                STATUS   ROLES   AGE   VERSION
aks-system-xxxxx-vmss000000         Ready    agent   2m    v1.28.9
aks-user-xxxxx-vmss000000           Ready    agent   2m    v1.28.9

Creating Kubernetes secret for Azure OpenAI API key...
✅ Secret created
```

#### **Phase 3: Open WebUI Deployment** (2-3 minutes)

The script will:
1. Add Open WebUI Helm repository
2. Update Helm values with actual Azure OpenAI endpoint
3. Deploy Open WebUI via Helm
4. Wait for pod to be ready

**Expected output:**

```
========================================
Phase 3: Open WebUI Deployment
========================================

Adding Open WebUI Helm repository...
✅ Helm repository added

Updating Helm values with OpenAI endpoint...
✅ Values updated

Deploying Open WebUI...
✅ Open WebUI deployed
```

#### **Phase 4: Waiting for LoadBalancer** (2-3 minutes)

The script will:
1. Monitor service for external IP assignment
2. Display progress every 10 seconds
3. Timeout after 5 minutes if IP not assigned

**Expected output:**

```
========================================
Phase 4: Waiting for LoadBalancer
========================================

Waiting for LoadBalancer IP (this may take 2-3 minutes)...
  Waiting... (0/300 seconds)
  Waiting... (10/300 seconds)
  Waiting... (20/300 seconds)
✅ LoadBalancer IP assigned: 20.168.45.123
```

### Deployment Summary

Upon completion, you'll see:

```
========================================
Deployment Complete!
========================================

Resources Created:
  Resource Group: rg-uniqueai-poc-demo
  AKS Cluster: aks-uniqueai-poc
  Azure OpenAI Endpoint: https://openai-uniqueai-xxx.openai.azure.com
  GPT-4 Deployment: gpt-4-deployment

Open WebUI Access:
  URL: http://20.168.45.123

Next Steps:
  1. Open your browser and navigate to: http://20.168.45.123
  2. Create an account (first user becomes admin)
  3. Start chatting with GPT-4!

Useful Commands:
  Check pods: kubectl get pods
  Check service: kubectl get svc open-webui
  View logs: kubectl logs -l app=open-webui
  Destroy: cd scripts && ./destroy.sh
```

---

## Verification

### 1. Verify Azure Resources

```bash
# Check resource group
az group show --name rg-uniqueai-poc-demo

# List all resources
az resource list --resource-group rg-uniqueai-poc-demo --output table

# Check Azure OpenAI
az cognitiveservices account show \
  --name <openai-account-name> \
  --resource-group rg-uniqueai-poc-demo

# Check AKS cluster
az aks show \
  --name aks-uniqueai-poc \
  --resource-group rg-uniqueai-poc-demo
```

### 2. Verify Kubernetes Resources

```bash
# Check nodes
kubectl get nodes

# Should show 2 nodes:
# - aks-system-xxxxx (system pool, regular)
# - aks-user-xxxxx (user pool, spot)

# Check pods
kubectl get pods

# Should show open-webui pod running

# Check service
kubectl get svc open-webui

# Should show LoadBalancer with EXTERNAL-IP

# Check secret
kubectl get secret azure-openai-secret
```

### 3. Test Azure OpenAI Connectivity

```bash
cd scripts
./test-connection.sh
```

Expected output:

```
HTTP Status: 200
✅ Connection successful!

Response:
Hello! This is a test response from GPT-4...

Azure OpenAI is working correctly!
```

### 4. Access Open WebUI

1. Open browser
2. Navigate to `http://<EXTERNAL-IP>`
3. You should see the Open WebUI login page

---

## Post-Deployment

### First-Time Setup

1. **Create Account:**
   - Click "Sign up"
   - Enter email and password
   - First user becomes administrator

2. **Configure Model:**
   - Open WebUI should automatically detect Azure OpenAI
   - Model: `gpt-4-deployment`
   - If not auto-detected, configure manually in Settings

3. **Test Chat:**
   - Start a new conversation
   - Send a test message
   - Verify GPT-4 responds

### Monitoring

```bash
# Watch pod status
kubectl get pods -w

# View logs
kubectl logs -f -l app=open-webui

# Check resource usage
kubectl top pods
kubectl top nodes

# Check events
kubectl get events --sort-by='.lastTimestamp'
```

### Cost Monitoring

Track costs in Azure Portal:

1. Navigate to Cost Management + Billing
2. Select your subscription
3. View cost analysis
4. Filter by resource group: `rg-uniqueai-poc-demo`

---

## Teardown

### Automated Teardown (Recommended)

```bash
cd scripts
./destroy.sh
```

The script will:
1. **Prompt for confirmation** ⚠️
2. Uninstall Open WebUI Helm release
3. Delete Kubernetes secret
4. Wait for LoadBalancer cleanup (30 seconds)
5. Destroy all Terraform-managed resources
6. Verify resource group deletion

**Expected output:**

```
⚠️  WARNING: This will destroy all deployed resources!

Resources to be destroyed:
  - Open WebUI Helm release
  - AKS Cluster (with all nodes)
  - Azure OpenAI Service
  - Resource Group and all contained resources

Are you sure you want to continue? (yes/no):
```

Type **`yes`** to proceed.

### Manual Teardown

If the script fails, teardown manually:

```bash
# 1. Uninstall Helm release
helm uninstall open-webui

# 2. Delete Kubernetes secret
kubectl delete secret azure-openai-secret

# 3. Destroy Terraform resources
cd terraform
terraform destroy -auto-approve

# 4. Verify resource group deletion
az group show --name rg-uniqueai-poc-demo
# Should return error: ResourceGroupNotFound
```

### Cleanup Terraform State Backend (Optional)

If you want to remove the Terraform state backend:

```bash
az group delete --name rg-terraform-state --yes --no-wait
```

**Warning:** This deletes the Terraform state storage. Only do this if you're completely done with the project.

---

## Manual Deployment (Without Scripts)

If you prefer manual control or troubleshooting:

### Step 1: Terraform

```bash
cd terraform

# Initialize
terraform init

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Get outputs
terraform output
```

### Step 2: Configure kubectl

```bash
# Get credentials
az aks get-credentials \
  --resource-group <resource-group-name> \
  --name <aks-cluster-name> \
  --overwrite-existing

# Verify
kubectl get nodes
```

### Step 3: Create Secret

```bash
# Get API key from Terraform output
API_KEY=$(cd terraform && terraform output -raw openai_api_key)

# Create secret
kubectl create secret generic azure-openai-secret \
  --from-literal=api-key="$API_KEY"
```

### Step 4: Deploy Open WebUI

Open WebUI is automatically deployed by Terraform via the Helm provider. No manual steps needed!

If you want to redeploy Open WebUI separately:

```bash
cd terraform

# Taint the Helm release to force redeployment
terraform taint helm_release.open_webui

# Reapply
terraform apply
```

### Step 5: Get LoadBalancer IP

```bash
kubectl get svc open-webui -w
```

Wait for EXTERNAL-IP to be assigned, then access at `http://<EXTERNAL-IP>`.

---

## Next Steps

- Review [ARCHITECTURE.md](../ARCHITECTURE.md) for architecture details
- Check [cost-analysis.md](cost-analysis.md) for cost breakdown
- See [troubleshooting.md](troubleshooting.md) if you encounter issues

---

**Deployment complete! Enjoy your POC.**
