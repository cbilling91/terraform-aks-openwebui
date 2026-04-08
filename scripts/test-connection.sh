#!/bin/bash
# Test script to verify Azure OpenAI connectivity

set -e

echo "=========================================="
echo "Azure OpenAI Connection Test"
echo "=========================================="
echo ""

# Change to terraform directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

cd "$TERRAFORM_DIR"

# Check curl
if ! command -v curl &> /dev/null; then
    echo "❌ curl not found."
    exit 1
fi

# Check jq (optional, for pretty JSON)
HAS_JQ=false
if command -v jq &> /dev/null; then
    HAS_JQ=true
fi

# Get Terraform outputs
echo "Retrieving Azure OpenAI configuration from Terraform..."
if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
    echo "❌ Terraform state not found. Please deploy the infrastructure first."
    exit 1
fi

OPENAI_ENDPOINT=$(terraform output -raw openai_endpoint 2>/dev/null || echo "")
OPENAI_API_KEY=$(terraform output -raw openai_api_key 2>/dev/null || echo "")
OPENAI_DEPLOYMENT_NAME=$(terraform output -raw openai_deployment_name 2>/dev/null || echo "")
OPENAI_API_VERSION=$(terraform output -raw openai_api_version 2>/dev/null || echo "2024-02-15-preview")

if [ -z "$OPENAI_ENDPOINT" ] || [ -z "$OPENAI_API_KEY" ] || [ -z "$OPENAI_DEPLOYMENT_NAME" ]; then
    echo "❌ Could not retrieve Azure OpenAI configuration from Terraform state"
    exit 1
fi

echo "✅ Configuration retrieved"
echo "   Endpoint: $OPENAI_ENDPOINT"
echo "   Deployment: $OPENAI_DEPLOYMENT_NAME"
echo "   API Version: $OPENAI_API_VERSION"
echo ""

# Test API endpoint
echo "Testing Azure OpenAI API endpoint..."
API_URL="${OPENAI_ENDPOINT}/openai/deployments/${OPENAI_DEPLOYMENT_NAME}/chat/completions?api-version=${OPENAI_API_VERSION}"

# Create test payload
PAYLOAD='{
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant."
    },
    {
      "role": "user",
      "content": "Hello! This is a connection test. Please respond with a brief greeting."
    }
  ],
  "max_tokens": 50,
  "temperature": 0.7
}'

echo "Sending test request..."
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "api-key: $OPENAI_API_KEY" \
    -d "$PAYLOAD")

# Extract HTTP status code
HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | sed 's/HTTP_STATUS://')
RESPONSE_BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS:/d')

echo ""
echo "HTTP Status: $HTTP_STATUS"
echo ""

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ Connection successful!"
    echo ""
    echo "Response:"
    if [ "$HAS_JQ" = true ]; then
        echo "$RESPONSE_BODY" | jq '.choices[0].message.content' -r
    else
        echo "$RESPONSE_BODY"
    fi
    echo ""
    echo "=========================================="
    echo "Azure OpenAI is working correctly!"
    echo "=========================================="
elif [ "$HTTP_STATUS" = "401" ]; then
    echo "❌ Authentication failed (401)"
    echo "   Check if the API key is correct"
    echo ""
    echo "Response:"
    echo "$RESPONSE_BODY"
    exit 1
elif [ "$HTTP_STATUS" = "404" ]; then
    echo "❌ Not found (404)"
    echo "   Check if the deployment name and endpoint are correct"
    echo ""
    echo "Response:"
    echo "$RESPONSE_BODY"
    exit 1
elif [ "$HTTP_STATUS" = "429" ]; then
    echo "❌ Rate limit exceeded (429)"
    echo "   You've hit the rate limit. Wait a moment and try again."
    echo ""
    echo "Response:"
    echo "$RESPONSE_BODY"
    exit 1
else
    echo "❌ Request failed with status $HTTP_STATUS"
    echo ""
    echo "Response:"
    echo "$RESPONSE_BODY"
    exit 1
fi
