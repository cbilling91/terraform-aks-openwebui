# Troubleshooting Guide

Common issues and solutions for the Open WebUI on AKS with Azure OpenAI deployment.

## Table of Contents

1. [Terraform Issues](#terraform-issues)
2. [Azure OpenAI Issues](#azure-openai-issues)
3. [AKS Issues](#aks-issues)
4. [Kubernetes Issues](#kubernetes-issues)
5. [Open WebUI Issues](#open-webui-issues)
6. [Networking Issues](#networking-issues)
7. [Authentication Issues](#authentication-issues)
8. [General Troubleshooting](#general-troubleshooting)

---

## Terraform Issues

### Issue: Terraform State Lock

**Symptom:**
```
Error: Error locking state: Error acquiring the state lock
```

**Cause:** Previous Terraform operation was interrupted, leaving state locked.

**Solution:**
```bash
cd terraform

# Option 1: Wait for lock to automatically release (after 2-20 minutes)

# Option 2: Force unlock (use with caution)
terraform force-unlock <LOCK_ID>

# Get LOCK_ID from error message
```

**Prevention:** Don't interrupt Terraform operations (Ctrl+C). Let them complete or fail naturally.

---

### Issue: OpenAI Account Name Already Exists

**Symptom:**
```
Error: A resource with the ID "/subscriptions/.../cognitiveAccounts/openai-aks-openwebui-xxx" already exists
```

**Cause:** Azure OpenAI account names must be globally unique.

**Solution:**
1. Edit `terraform/terraform.tfvars`
2. Change `openai_account_name` to a different unique value
3. Try deployment again

```hcl
# Use your initials + random numbers
openai_account_name = "openai-aks-openwebui-abc1234"
```

---

### Issue: Insufficient Quota

**Symptom:**
```
Error: Compute.VMSizeNotAllowed
The requested VM size Standard_B2s is not available in the current region
```

**Cause:** Subscription doesn't have quota for Standard_B2s VMs.

**Solution:**
```bash
# Check current quota
az vm list-usage --location eastus --query "[?name.value=='StandardBSFamily']"

# Request quota increase:
# 1. Azure Portal → Subscriptions → Usage + quotas
# 2. Search for "Standard BSv2 Family vCPUs"
# 3. Request increase to 4 vCPUs
# 4. Wait for approval (usually 1-24 hours)
```

**Alternative:** Use different VM size in `terraform/main.tf`:
```hcl
system_node_vm_size = "Standard_DS2_v2"  # Alternative option
user_node_vm_size   = "Standard_DS2_v2"
```

---

### Issue: Azure OpenAI Access Denied

**Symptom:**
```
Error: creating Cognitive Services Account: 403 Forbidden
```

**Cause:** Subscription doesn't have Azure OpenAI access approved.

**Solution:**
1. Apply for access: https://aka.ms/oai/access
2. Wait for Microsoft approval (can take several days)
3. Verify approval: Try creating OpenAI resource in Azure Portal manually

**Workaround:** Use existing Azure OpenAI resource if available.

---

### Issue: Backend Configuration Error

**Symptom:**
```
Error: Backend initialization required
```

**Cause:** Terraform backend not configured or storage account doesn't exist.

**Solution:**
```bash
# Run bootstrap script to create backend
cd scripts
./bootstrap-backend.sh

# Then reinitialize Terraform
cd ../terraform
terraform init -reconfigure
```

---

## Azure OpenAI Issues

### Issue: API Key Authentication Failed

**Symptom:**
```
HTTP Status: 401 Unauthorized
```

**Cause:** Invalid or expired API key.

**Solution:**
```bash
# Get correct API key from Terraform
cd terraform
terraform output -raw openai_api_key

# Update Kubernetes secret
kubectl delete secret azure-openai-secret
kubectl create secret generic azure-openai-secret \
  --from-literal=api-key="<NEW_API_KEY>"

# Restart Open WebUI pod
kubectl rollout restart deployment open-webui
```

---

### Issue: Rate Limit Exceeded

**Symptom:**
```
HTTP Status: 429 Too Many Requests
```

**Cause:** Exceeded 10K TPM (tokens per minute) capacity limit.

**Solution:**

**Immediate:** Wait 60 seconds for rate limit to reset.

**Long-term:** Increase capacity in `terraform/main.tf`:
```hcl
capacity = 20  # Increase from 10 to 20 (20K TPM)
```

Then apply:
```bash
cd terraform
terraform apply
```

**Note:** Higher capacity = potentially higher costs.

---

### Issue: Model Deployment Not Found

**Symptom:**
```
Error: The API deployment for this resource does not exist
```

**Cause:** GPT-4 deployment not created or incorrect deployment name.

**Solution:**
```bash
# Verify deployment exists
az cognitiveservices account deployment list \
  --name <openai-account-name> \
  --resource-group <resource-group-name>

# Check deployment name in Terraform configuration
cd terraform
terraform state show helm_release.open_webui | grep DEFAULT_MODELS
```

---

### Issue: Azure OpenAI Endpoint Unreachable

**Symptom:**
```
Error: timeout connecting to endpoint
```

**Cause:** Network connectivity issue or incorrect endpoint URL.

**Solution:**
```bash
# Test connectivity from local machine
cd scripts
./test-connection.sh

# Test from within AKS cluster
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v https://<your-endpoint>.openai.azure.com
```

**If test from AKS fails:**
- Check NSG rules (if custom networking)
- Verify AKS has outbound internet access
- Check Azure OpenAI firewall settings

---

## AKS Issues

### Issue: Spot Node Evicted

**Symptom:**
```
Node was evicted due to Azure Spot VM capacity constraints
Pod "open-webui-xxx" is in state "Pending"
```

**Cause:** Azure reclaimed spot instance due to capacity needs.

**Solution:**

**Immediate:** Wait for Azure to provision new spot node (usually 1-5 minutes).

**Temporary workaround:** Scale user pool to regular priority:
```bash
az aks nodepool update \
  --resource-group <rg-name> \
  --cluster-name <cluster-name> \
  --name user \
  --priority Regular
```

**Note:** This increases costs significantly. Switch back to spot after demo.

---

### Issue: Cluster Not Responding

**Symptom:**
```
Unable to connect to the server: dial tcp: i/o timeout
```

**Cause:** AKS API server unreachable.

**Solution:**
```bash
# Refresh AKS credentials
az aks get-credentials \
  --resource-group <rg-name> \
  --name <cluster-name> \
  --overwrite-existing

# Verify cluster is running
az aks show \
  --resource-group <rg-name> \
  --name <cluster-name> \
  --query "powerState"

# If stopped, start cluster
az aks start \
  --resource-group <rg-name> \
  --name <cluster-name>
```

---

### Issue: Node Not Ready

**Symptom:**
```
NAME                       STATUS     ROLES   AGE
aks-user-xxxxx-vmss000000  NotReady   agent   5m
```

**Cause:** Node is initializing, experiencing issues, or recently evicted.

**Solution:**
```bash
# Check node conditions
kubectl describe node <node-name>

# Check node events
kubectl get events --field-selector involvedObject.name=<node-name>

# If node stuck in NotReady for >10 minutes, delete and let AKS recreate
kubectl delete node <node-name>
```

---

## Kubernetes Issues

### Issue: Pod Stuck in Pending

**Symptom:**
```
NAME                 READY   STATUS    RESTARTS   AGE
open-webui-xxx       0/1     Pending   0          5m
```

**Cause:** Pod can't be scheduled (no suitable node, tolerations, or resources).

**Solution:**
```bash
# Check why pod is pending
kubectl describe pod <pod-name>

# Common reasons:

# 1. Spot node evicted (wait for new node)
# 2. Insufficient resources
kubectl top nodes

# 3. Toleration mismatch
kubectl get nodes --show-labels

# 4. Image pull failure
kubectl describe pod <pod-name> | grep -A10 "Events:"
```

---

### Issue: Pod CrashLoopBackOff

**Symptom:**
```
NAME                 READY   STATUS             RESTARTS   AGE
open-webui-xxx       0/1     CrashLoopBackOff   5          10m
```

**Cause:** Container starts then crashes immediately.

**Solution:**
```bash
# Check pod logs
kubectl logs <pod-name>

# Check previous container logs (if restarted)
kubectl logs <pod-name> --previous

# Common causes:

# 1. Missing environment variables
kubectl describe pod <pod-name> | grep -A10 "Environment"

# 2. Secret not found
kubectl get secret azure-openai-secret

# 3. Configuration error in Terraform
cd terraform
terraform state show helm_release.open_webui
# Or check Helm values
helm get values open-webui
```

---

### Issue: Secret Not Found

**Symptom:**
```
Error: secret "azure-openai-secret" not found
```

**Cause:** Kubernetes secret wasn't created or was deleted.

**Solution:**
```bash
# Create secret from Terraform output
cd terraform
API_KEY=$(terraform output -raw openai_api_key)

kubectl create secret generic azure-openai-secret \
  --from-literal=api-key="$API_KEY"

# Verify secret exists
kubectl get secret azure-openai-secret

# Restart deployment to pick up secret
kubectl rollout restart deployment open-webui
```

---

### Issue: ImagePullBackOff

**Symptom:**
```
NAME                 READY   STATUS             RESTARTS   AGE
open-webui-xxx       0/1     ImagePullBackOff   0          5m
```

**Cause:** Can't pull Open WebUI container image.

**Solution:**
```bash
# Check image pull error
kubectl describe pod <pod-name> | grep -A10 "Failed"

# Verify image exists
docker pull ghcr.io/open-webui/open-webui:latest

# Common causes:
# 1. Rate limit from ghcr.io (wait 1 hour)
# 2. Network connectivity from AKS
# 3. Image tag doesn't exist

# Workaround: Use specific version instead of "latest"
helm upgrade open-webui open-webui/open-webui \
  --set image.tag=v0.1.117 \
  --reuse-values
```

---

## Open WebUI Issues

### Issue: Open WebUI Not Accessible

**Symptom:** Browser shows "Connection refused" or timeout when accessing LoadBalancer IP.

**Cause:** LoadBalancer not provisioned, pod not ready, or network issue.

**Solution:**
```bash
# 1. Verify LoadBalancer IP assigned
kubectl get svc open-webui
# EXTERNAL-IP should show actual IP, not <pending>

# 2. If pending, wait 2-5 minutes for Azure to provision

# 3. Verify pod is running
kubectl get pods
# STATUS should be "Running", READY should be "1/1"

# 4. Test connectivity from pod
kubectl port-forward svc/open-webui 8080:80
# Then access http://localhost:8080

# 5. If port-forward works but LoadBalancer doesn't:
# Check NSG rules on node resource group
```

---

### Issue: Open WebUI Shows "No Models Available"

**Symptom:** Open WebUI loads but shows "No models available" error.

**Cause:** Open WebUI can't connect to Azure OpenAI or wrong configuration.

**Solution:**
```bash
# 1. Check environment variables in pod
kubectl exec -it <pod-name> -- env | grep OPENAI

# 2. Verify endpoint URL is correct
cd terraform
terraform output openai_endpoint

# 3. Test Azure OpenAI connectivity from pod
kubectl exec -it <pod-name> -- \
  curl -v https://<your-endpoint>.openai.azure.com

# 4. Check logs for connection errors
kubectl logs <pod-name> | grep -i error

# 5. Verify secret is correct
kubectl get secret azure-openai-secret -o jsonpath='{.data.api-key}' | base64 -d
```

---

### Issue: Chat Responses Are Slow

**Symptom:** Messages take 10+ seconds to get responses.

**Cause:** GPT-4 inference time, network latency, or rate limiting.

**Solution:**
```bash
# 1. Check if hitting rate limits
kubectl logs <pod-name> | grep "429"

# 2. Check Azure OpenAI metrics in Azure Portal
# Navigate to Azure OpenAI resource → Metrics
# Look for "Total Token Count" and "Rate Limit"

# 3. Increase TPM capacity (if needed)
cd terraform
# Edit main.tf: capacity = 20
terraform apply

# 4. Verify pod resources aren't constrained
kubectl top pod <pod-name>
```

---

## Networking Issues

### Issue: LoadBalancer IP Not Assigned

**Symptom:**
```
NAME         TYPE           EXTERNAL-IP   PORT(S)
open-webui   LoadBalancer   <pending>     80:30123/TCP
```

**Cause:** Azure is provisioning LoadBalancer (can take 2-5 minutes).

**Solution:**
```bash
# Wait and watch
kubectl get svc open-webui -w

# If stuck in pending >10 minutes:

# 1. Check service events
kubectl describe svc open-webui

# 2. Check AKS managed identity permissions
az aks show \
  --resource-group <rg-name> \
  --name <cluster-name> \
  --query "identity"

# 3. Check node resource group exists
az group show --name <node-resource-group-name>

# 4. Delete and recreate service
kubectl delete svc open-webui
helm upgrade open-webui open-webui/open-webui --reuse-values
```

---

### Issue: Can't Access LoadBalancer from Browser

**Symptom:** Timeout or "Connection refused" in browser.

**Cause:** NSG blocking traffic or incorrect IP.

**Solution:**
```bash
# 1. Verify LoadBalancer IP
kubectl get svc open-webui -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# 2. Test connectivity
curl -v http://<EXTERNAL-IP>

# 3. Check LoadBalancer in Azure Portal
# Node Resource Group → Load Balancer → Frontend IP

# 4. Check NSG rules
az network nsg list \
  --resource-group <node-resource-group> \
  --output table

# 5. If all else fails, use port-forward as workaround
kubectl port-forward svc/open-webui 8080:80
# Access at http://localhost:8080
```

---

## Authentication Issues

### Issue: Can't Login to Azure CLI

**Symptom:**
```
az login
# Opens browser but fails to authenticate
```

**Solution:**
```bash
# Option 1: Device code flow
az login --use-device-code

# Option 2: Service principal
az login --service-principal \
  -u <app-id> \
  -p <password> \
  --tenant <tenant-id>

# Option 3: Managed identity (if on Azure VM)
az login --identity
```

---

### Issue: Wrong Azure Subscription

**Symptom:** Resources being created in wrong subscription.

**Solution:**
```bash
# List all subscriptions
az account list --output table

# Set correct subscription
az account set --subscription "<subscription-id>"

# Verify
az account show
```

---

### Issue: kubectl Authentication Error

**Symptom:**
```
error: You must be logged in to the server (Unauthorized)
```

**Solution:**
```bash
# Refresh credentials
az aks get-credentials \
  --resource-group <rg-name> \
  --name <cluster-name> \
  --overwrite-existing

# Or use helper script
cd scripts
./setup-kubeconfig.sh
```

---

## General Troubleshooting

### Diagnostic Commands

```bash
# Terraform
terraform validate           # Validate configuration
terraform plan              # Preview changes
terraform state list        # List resources in state
terraform output            # Show all outputs

# Azure CLI
az group list               # List resource groups
az resource list --resource-group <rg> # List resources
az aks list                 # List AKS clusters
az cognitiveservices account list # List OpenAI accounts

# Kubernetes
kubectl get all            # List all resources
kubectl get events --sort-by='.lastTimestamp' # Recent events
kubectl describe pod <pod> # Pod details
kubectl logs <pod>         # Pod logs
kubectl top nodes          # Node resource usage
kubectl top pods           # Pod resource usage

# Open WebUI specific
helm list                  # List Helm releases
helm status open-webui     # Release status
helm get values open-webui # Current values
```

### Logs Collection

```bash
# Collect all logs for troubleshooting

# Terraform
cd terraform
terraform show > terraform-state.txt

# Kubernetes
kubectl get all -o wide > k8s-resources.txt
kubectl describe pod <pod-name> > pod-describe.txt
kubectl logs <pod-name> > pod-logs.txt
kubectl get events --sort-by='.lastTimestamp' > k8s-events.txt

# Azure
az group show --name <rg> > resource-group.json
az aks show --name <cluster> --resource-group <rg> > aks-cluster.json
```

### Clean Slate (Nuclear Option)

If nothing works, start fresh:

```bash
# 1. Destroy everything
cd scripts
./destroy.sh

# 2. Wait for confirmation of deletion
az group show --name <rg-name>
# Should return: ResourceGroupNotFound

# 3. Clean local state
cd ../terraform
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup tfplan

# 4. Start over
cd ../scripts
./deploy.sh
```

---

## Getting Help

If you're still stuck after trying these solutions:

1. **Check logs:** Collect all logs as shown in "Logs Collection" section
2. **Azure Support:** Create support ticket in Azure Portal
3. **Community:**
   - Azure AKS: https://github.com/Azure/AKS/issues
   - Open WebUI: https://github.com/open-webui/open-webui/issues
   - Terraform: https://discuss.hashicorp.com/c/terraform-core

4. **Test in isolation:**
   - Test Azure OpenAI separately: `./scripts/test-connection.sh`
   - Test AKS separately: Deploy simple nginx pod
   - Test networking separately: Use Azure Network Watcher

---

## Prevention Checklist

Avoid common issues by following these best practices:

✅ **Before deployment:**
- Verify Azure OpenAI access approved
- Check subscription quotas
- Ensure unique names in terraform.tfvars
- Run `terraform validate` before apply

✅ **During deployment:**
- Don't interrupt Terraform (Ctrl+C)
- Wait for LoadBalancer (2-5 minutes)
- Monitor logs during deployment
- Save Terraform outputs for reference

✅ **After deployment:**
- Test connectivity with test-connection.sh
- Verify pod logs show no errors
- Access Open WebUI and test chat
- Set up cost alerts

✅ **For demos:**
- Test full workflow day before
- Have backup plan if spot node evicted
- Keep destroy script ready for cleanup
- Monitor costs daily

---

**Still having issues? Review [deployment-guide.md](deployment-guide.md) for detailed step-by-step instructions.**
