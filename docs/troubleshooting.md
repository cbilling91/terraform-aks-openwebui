# Troubleshooting Guide

Common issues and solutions for the Open WebUI on AKS deployment.

## Table of Contents

1. [Terraform Issues](#terraform-issues)
2. [Azure Issues](#azure-issues)
3. [TLS / Certificate Issues](#tls--certificate-issues)
4. [Kubernetes / Pod Issues](#kubernetes--pod-issues)
5. [Open WebUI Issues](#open-webui-issues)
6. [Diagnostic Commands](#diagnostic-commands)

---

## Terraform Issues

### Provider: `hashicorp/kubectl` not found

**Symptom:**
```
Could not retrieve the list of available versions for provider hashicorp/kubectl:
provider registry registry.terraform.io does not have a provider named registry.terraform.io/hashicorp/kubectl
```

**Cause:** Terraform is defaulting to the `hashicorp/` namespace for the `kubectl` provider, which doesn't exist. The correct provider is `gavinbunney/kubectl`, declared in `versions.tf`.

**Solution:** Run `terraform init` from the project root (not a subdirectory). The `versions.tf` at the root declares the correct source.

---

### Terraform State Lock

**Symptom:**
```
Error: Error locking state: Error acquiring the state lock
```

**Solution:**
```bash
terraform force-unlock <LOCK_ID>
# LOCK_ID is printed in the error message
```

Do not interrupt `terraform apply` mid-run (Ctrl+C) — let it complete or fail cleanly.

---

### Azure OpenAI: 403 Forbidden

**Symptom:**
```
Error: creating Cognitive Services Account: 403 Forbidden
```

**Cause:** Azure OpenAI access not approved for your subscription.

**Solution:** Apply for access at https://aka.ms/oai/access and wait for approval. You can verify by attempting to create an OpenAI resource manually in the Azure Portal.

---

### Insufficient vCPU Quota

**Symptom:**
```
Error: Compute.VMSizeNotAllowed — The requested VM size is not available
```

**Solution:**
```bash
az vm list-usage --location eastus --query "[?name.value=='standardDSv3Family']" --output table
```

Request a quota increase via Azure Portal → Subscriptions → Usage + quotas. Or change `user_node_vm_size` in `terraform.tfvars` to a size with available quota.

---

### OpenAI Account Name Already Exists

**Symptom:**
```
Error: A resource with the ID ".../cognitiveAccounts/..." already exists
```

**Cause:** Azure OpenAI account names must be globally unique. The name (derived from `project_name` + random suffix) collides with an existing account, possibly from a previous deployment.

**Solution:** Change `project_name` in `terraform.tfvars` to something more unique.

---

## Azure Issues

### AKS Cluster Not Responding

**Symptom:** `kubectl` commands hang or return `dial tcp: i/o timeout`.

**Solution:**
```bash
# Refresh kubeconfig
az aks get-credentials \
  --resource-group rg-<project_name>-<environment> \
  --name <project_name> \
  --overwrite-existing

# Check cluster power state
az aks show \
  --resource-group rg-<project_name>-<environment> \
  --name <project_name> \
  --query "powerState"
```

---

### Spot Node Evicted

**Symptom:** Open WebUI pod stuck in `Pending` after working previously.

**Cause:** Azure reclaimed the spot instance.

**Immediate fix:** Wait 1-5 minutes — AKS will provision a replacement spot node automatically.

**If demo requires guaranteed availability:** Set `spot_instances = false` in `terraform.tfvars` and run `terraform apply` to switch the user node pool to regular priority. This increases cost (~$30/month) but eliminates eviction risk.

---

## TLS / Certificate Issues

### Certificate Not Ready

**Symptom:** Browser shows TLS warning; `kubectl get certificate -A` shows `READY: False`.

**Check status:**
```bash
kubectl describe certificate -A
kubectl describe certificaterequest -A
kubectl describe order -A   # cert-manager ACME order
```

**Common causes:**

1. **DNS not yet propagated** — The Azure DNS FQDN must resolve to the static public IP before Let's Encrypt can complete the HTTP-01 challenge. The IP is assigned when Traefik starts, but DNS can take a few minutes.

   ```bash
   # Check public IP
   kubectl get svc -n traefik
   
   # Verify DNS resolves
   nslookup <project_name>.<location>.cloudapp.azure.com
   ```

2. **Traefik not yet ready** — cert-manager's HTTP-01 challenge requires Traefik to be serving traffic. Check Traefik pod status:
   ```bash
   kubectl get pods -n traefik
   kubectl logs -n traefik -l app.kubernetes.io/name=traefik
   ```

3. **Rate limit hit** — Let's Encrypt enforces rate limits (5 duplicate certs per week). If you've been destroying and recreating repeatedly, you may need to wait.

**Once the issue is resolved**, cert-manager retries automatically. You can force a retry by deleting the failed order:
```bash
kubectl delete order -A --all
```

---

### HTTPS Redirect Loop

**Symptom:** Browser shows "too many redirects".

**Cause:** Open WebUI or a reverse proxy is also trying to redirect to HTTPS, creating a loop with Traefik's HTTPS redirect.

**Check:** Traefik is configured to redirect HTTP → HTTPS at the Gateway level. Ensure Open WebUI's Helm values don't have an additional redirect configured.

---

## Kubernetes / Pod Issues

### Pod Stuck in Pending

```bash
kubectl describe pod <pod-name>
# Look at "Events:" section — it will explain why scheduling failed
```

**Common causes:**
- Spot node evicted (see above)
- Insufficient node resources: `kubectl top nodes`
- Toleration mismatch (spot taint): check node labels with `kubectl get nodes --show-labels`

---

### Pod CrashLoopBackOff

```bash
kubectl logs <pod-name>
kubectl logs <pod-name> --previous   # logs from last crash
```

**For Open WebUI:** Check that the LiteLLM service is reachable:
```bash
kubectl exec -it <open-webui-pod> -- curl http://litellm-service:4000/health
```

**For LiteLLM:** Check that the Azure OpenAI secret exists and contains a valid key:
```bash
kubectl get secret azure-openai-secret
kubectl get secret azure-openai-secret -o jsonpath='{.data.api-key}' | base64 -d
```

---

### Secret Not Found

```bash
# Check what secrets exist
kubectl get secrets

# Terraform manages the azure-openai-secret — if missing, re-apply
terraform apply
```

---

### ImagePullBackOff

```bash
kubectl describe pod <pod-name> | grep -A10 "Failed"
```

Usually a transient rate-limit from `ghcr.io`. Wait a few minutes and the pod will retry automatically.

---

## Open WebUI Issues

### "No Models Available"

Open WebUI connects to LiteLLM, which connects to Azure OpenAI. Trace the chain:

```bash
# 1. Is LiteLLM running?
kubectl get pods -l app=litellm

# 2. Can Open WebUI reach LiteLLM?
kubectl exec -it <open-webui-pod> -- curl http://litellm-service:4000/health

# 3. Can LiteLLM reach Azure OpenAI?
kubectl logs -l app=litellm | tail -50

# 4. Is the API key valid?
kubectl get secret azure-openai-secret -o jsonpath='{.data.api-key}' | base64 -d
```

---

### Slow Responses

GPT model inference typically takes 2-5 seconds. If significantly slower:

1. **Rate limiting:** Check for 429 errors in LiteLLM logs:
   ```bash
   kubectl logs -l app=litellm | grep "429"
   ```
   If hitting limits, increase `capacity` in `terraform.tfvars` and re-apply.

2. **Pod resource contention:**
   ```bash
   kubectl top pods
   kubectl top nodes
   ```

---

## Diagnostic Commands

### Full Status Check

```bash
# Nodes
kubectl get nodes

# All pods across key namespaces
kubectl get pods -A | grep -E "traefik|cert-manager|litellm|open-webui"

# Services
kubectl get svc -A | grep -E "traefik|litellm|open-webui"

# TLS certificate
kubectl get certificate -A
kubectl get certificaterequest -A

# Gateway
kubectl get gateway -A
kubectl get httproute -A

# Recent events (sorted)
kubectl get events --sort-by='.lastTimestamp' | tail -30
```

### Terraform State

```bash
terraform output          # Show all outputs including app_url
terraform state list      # List all managed resources
terraform plan            # Check for drift
```

### Azure

```bash
# List resources in the project resource group
az resource list --resource-group rg-<project_name>-<environment> --output table

# Check AKS cluster
az aks show --name <project_name> --resource-group rg-<project_name>-<environment>

# Check public IP
az network public-ip show --name pip-<project_name>-ingress --resource-group <node_resource_group>
```

---

**Still stuck?**
- Open WebUI: https://github.com/open-webui/open-webui/issues
- Traefik: https://github.com/traefik/traefik/issues
- cert-manager: https://cert-manager.io/docs/troubleshooting/
- Azure AKS: https://github.com/Azure/AKS/issues
