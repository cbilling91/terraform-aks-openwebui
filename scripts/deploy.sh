#!/bin/bash
# Simplified deployment script - Terraform handles everything now
# This script validates prerequisites and runs Terraform

set -e

echo "=========================================="
echo "Open WebUI + AKS + Azure OpenAI Deployment"
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
    echo "❌ Azure CLI not found. Please install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Please install: https://www.terraform.io/downloads"
    exit 1
fi

# Check kubectl (required for Gateway API CRD installation)
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Required for Gateway API CRD installation."
    echo "   Install: https://kubernetes.io/docs/tasks/tools/"
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

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "❌ terraform.tfvars not found"
    echo "   Please copy terraform.tfvars.example to terraform.tfvars and update with your values"
    exit 1
fi

echo "=========================================="
echo "Terraform Deployment"
echo "=========================================="
echo ""

# Initialize Terraform
echo "Initializing Terraform..."
terraform init
echo "✅ Terraform initialized"
echo ""

# Validate configuration
echo "Validating Terraform configuration..."
terraform validate
echo "✅ Configuration valid"
echo ""

# Plan infrastructure
echo "Planning infrastructure changes..."
terraform plan -out=tfplan
echo "✅ Plan created"
echo ""

# Confirm deployment
echo "This Terraform deployment will create:"
echo "  ✅ Resource Group"
echo "  ✅ Azure OpenAI Service"
echo "  ✅ AKS Cluster (Free tier with mixed node pools)"
echo "  ✅ Gateway API CRDs (via Terraform kubectl provider)"
echo "  ✅ Traefik Gateway (HTTPS via Let's Encrypt)"
echo "  ✅ Kubernetes Secret (Azure OpenAI API key)"
echo "  ✅ Open WebUI (via Helm)"
echo ""
read -p "Continue with deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

echo ""
echo "=========================================="
echo "Applying Terraform configuration"
echo "=========================================="
echo ""
echo "This will take approximately 10-15 minutes..."
echo ""
terraform apply tfplan
echo ""
echo "✅ Terraform deployment complete"
echo ""

# Get AKS credentials for kubectl access
echo "=========================================="
echo "Configuring kubectl Access"
echo "=========================================="
echo ""

if command -v kubectl &> /dev/null; then
    echo "Retrieving AKS credentials..."
    RESOURCE_GROUP=$(terraform output -raw resource_group_name)
    AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name)

    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AKS_CLUSTER_NAME" \
        --overwrite-existing

    echo "✅ kubectl configured"
    echo ""

    # Display cluster info
    echo "Cluster nodes:"
    kubectl get nodes
    echo ""

    echo "=========================================="
    echo "Waiting for TLS certificate"
    echo "=========================================="
    echo ""

    APP_URL=$(terraform output -raw app_url 2>/dev/null || echo "")
    echo "App URL: $APP_URL"
    echo ""
    echo "Waiting for TLS certificate to be issued (this may take 2-3 minutes)..."
    TIMEOUT=300
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        CERT_READY=$(kubectl get certificate open-webui-tls -n traefik -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

        if [ "$CERT_READY" = "True" ]; then
            echo "✅ TLS certificate issued"
            break
        fi

        echo "  Waiting... ($ELAPSED/$TIMEOUT seconds)"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    echo ""
fi

# Display summary
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""

APP_URL=$(terraform output -raw app_url 2>/dev/null || echo "")
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "")
OPENAI_DEPLOYMENT=$(terraform output -raw openai_deployment_name 2>/dev/null || echo "")

echo "  App URL:          ${APP_URL:-n/a}"
echo "  Resource Group:   $RESOURCE_GROUP"
echo "  AKS Cluster:      $AKS_CLUSTER_NAME"
echo "  OpenAI Deployment: $OPENAI_DEPLOYMENT"
echo ""
if [ -n "$APP_URL" ]; then
    echo "Open $APP_URL in your browser to start chatting."
fi
echo ""

echo "Useful Commands:"
echo "  Check pods:        kubectl get pods -n default"
echo "  Check routes:      kubectl get httproute -n default"
echo "  Check certificate: kubectl get certificate -n traefik"
echo "  View logs:         kubectl logs -l app.kubernetes.io/name=open-webui -n default"
echo "  Helm releases:     helm list -A"
echo "  Destroy:           terraform destroy"
echo ""
echo "=========================================="
