#!/bin/bash
# Helper script to configure kubectl for the AKS cluster

set -e

echo "=========================================="
echo "AKS kubectl Configuration"
echo "=========================================="
echo ""

# Change to terraform directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

cd "$TERRAFORM_DIR"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found."
    exit 1
fi

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found."
    exit 1
fi

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

# Get Terraform outputs
echo "Retrieving cluster information from Terraform..."
if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
    echo "❌ Terraform state not found. Please deploy the infrastructure first."
    exit 1
fi

RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "")

if [ -z "$RESOURCE_GROUP" ] || [ -z "$AKS_CLUSTER_NAME" ]; then
    echo "❌ Could not retrieve AKS cluster details from Terraform state"
    exit 1
fi

echo "✅ Cluster information retrieved"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Cluster Name: $AKS_CLUSTER_NAME"
echo ""

# Get AKS credentials
echo "Configuring kubectl..."
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --overwrite-existing

echo "✅ kubectl configured"
echo ""

# Verify cluster access
echo "Verifying cluster access..."
kubectl cluster-info
echo ""

echo "Cluster nodes:"
kubectl get nodes
echo ""

echo "=========================================="
echo "kubectl Configuration Complete!"
echo "=========================================="
echo ""
echo "You can now use kubectl to interact with your AKS cluster."
echo ""
echo "Useful commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods"
echo "  kubectl get svc"
echo "  kubectl logs <pod-name>"
echo ""
