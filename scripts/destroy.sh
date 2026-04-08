#!/bin/bash
# Simplified teardown script - Terraform destroys everything
# This script validates prerequisites and runs terraform destroy

set -e

echo "=========================================="
echo "Open WebUI + AKS + Azure OpenAI Teardown"
echo "=========================================="
echo ""

# Change to terraform directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

cd "$TERRAFORM_DIR"

# Check prerequisites
echo "Checking prerequisites..."

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found."
    exit 1
fi

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found."
    exit 1
fi

echo "✅ Prerequisites checked"
echo ""

# Check Azure authentication
echo "Checking Azure CLI authentication..."
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo "✅ Authenticated to Azure"
echo "   Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
echo ""

# Get resource info before destruction (if available)
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "")

# Warning
echo "⚠️  WARNING: This will destroy all deployed resources!"
echo ""
echo "Resources to be destroyed:"
echo "  - Open WebUI (Helm release)"
echo "  - Kubernetes Secret"
echo "  - AKS Cluster (with all nodes and workloads)"
echo "  - Azure OpenAI Service (GPT-4 deployment)"
echo "  - Resource Group and all contained resources"
echo ""
if [ -n "$RESOURCE_GROUP" ]; then
    echo "Resource Group: $RESOURCE_GROUP"
fi
if [ -n "$AKS_CLUSTER_NAME" ]; then
    echo "AKS Cluster: $AKS_CLUSTER_NAME"
fi
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Teardown cancelled"
    exit 0
fi
echo ""

echo "=========================================="
echo "Destroying Infrastructure"
echo "=========================================="
echo ""

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
    echo ""
fi

# Destroy infrastructure
echo "Destroying Terraform-managed infrastructure..."
echo "This will:"
echo "  1. Uninstall Open WebUI Helm release"
echo "  2. Delete Kubernetes secret"
echo "  3. Wait for LoadBalancer cleanup"
echo "  4. Destroy AKS cluster"
echo "  5. Destroy Azure OpenAI service"
echo "  6. Delete resource group"
echo ""
echo "This process takes approximately 10-15 minutes..."
echo ""

terraform destroy -auto-approve

echo "✅ Infrastructure destroyed"
echo ""

echo "=========================================="
echo "Verification"
echo "=========================================="
echo ""

# Verify resource group deletion
if [ -n "$RESOURCE_GROUP" ]; then
    echo "Verifying resource group deletion..."
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        echo "⚠️  Resource group still exists: $RESOURCE_GROUP"
        echo "   It may take a few minutes to fully delete"
    else
        echo "✅ Resource group deleted: $RESOURCE_GROUP"
    fi
else
    echo "⚠️  Could not verify resource group deletion (name not found in state)"
fi
echo ""

echo "=========================================="
echo "Teardown Complete!"
echo "=========================================="
echo ""
echo "All POC resources have been destroyed via Terraform."
echo ""
echo "Note: The Terraform state backend (if created) remains for future deployments."
echo "      To delete it, run: az group delete --name rg-terraform-state --yes"
echo ""
echo "Local Terraform files (.terraform, state) are still present."
echo "To clean them up, run:"
echo "  cd terraform"
echo "  rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup tfplan"
echo ""
echo "=========================================="
