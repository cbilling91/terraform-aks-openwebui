# Cost Analysis

Cost breakdown and optimization strategies for the Open WebUI on AKS with Azure OpenAI deployment.

> **Note:** All costs are estimates based on Azure's published pricing and vary by region, usage, and current rates. Check [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for current figures.

---

## Infrastructure Components

### AKS

| Component | Configuration | Notes |
|-----------|--------------|-------|
| Control Plane | Free tier | No control plane charges; adequate for POC |
| System Node Pool | Standard_DS2_v2, 1 node, regular priority | Runs system and platform pods (Traefik, cert-manager) |
| User Node Pool | Standard_D2s_v3, 1 node, regular or spot | Runs Open WebUI workload |
| Static Public IP | Standard SKU | Traefik ingress; 1 IP |

**Spot instances** can be enabled for the user node pool via `spot_instances = true` in `terraform.tfvars`. Spot pricing typically offers ~70-90% savings over regular pricing but is subject to eviction. The system node pool must remain regular priority.

### Azure OpenAI (AI Foundry)

- **Pricing model:** Pay-per-token (no fixed monthly fee)
- **Configured capacity:** 10K TPM (tokens per minute) — acts as a rate cap to control runaway spend
- **Model:** Configurable via `openai_model_name` variable (default: `gpt-4o`)
- **Authentication:** Workload Identity (no API key stored) — no additional cost

Token costs vary significantly by model. Check [Azure OpenAI pricing](https://azure.microsoft.com/en-us/pricing/details/cognitive-services/openai-service/) for current per-model rates.

### Networking

| Component | Notes |
|-----------|-------|
| Data transfer in | Free |
| Data transfer out | First 5 GB/month free; charged per GB beyond that |
| Static public IP | Charged per hour while allocated |

---

## Cost Optimization Decisions

| Decision | Benefit |
|----------|---------|
| Free tier AKS | Eliminates control plane cost entirely |
| Optional spot instances (user pool) | Large savings on the workload node; tolerable for a POC |
| Minimal VM sizes | Right-sized for a single-user/demo workload |
| Kubenet networking | Lower overhead vs Azure CNI |
| No persistent storage | Eliminates managed disk costs; acceptable for stateless demo |
| 10K TPM capacity cap | Hard ceiling on Azure OpenAI spend |
| Workload Identity auth | No secrets to store or rotate; no additional cost |
| Single region | No geo-replication overhead |

---

## Alternative Architectures

### All Regular Nodes (no spot)
- Higher compute cost, guaranteed availability
- Suitable if spot eviction risk is unacceptable (e.g., live demos)

### All Spot Nodes
- Maximum compute savings
- **Not recommended** — if both nodes are evicted simultaneously, the cluster goes fully offline including system pods

### Azure Container Apps
- Simpler, serverless alternative
- Potentially lower cost for low-traffic workloads
- Does not satisfy AKS-specific requirements

---

## Production Considerations

Moving to production would typically involve:

| Change | Cost Impact |
|--------|-------------|
| AKS Standard tier (for SLA) | Additional monthly fixed cost |
| 3+ node minimum (HA) | Proportionally higher compute |
| Cluster Autoscaler | Variable cost; reduces waste during off-hours |
| Persistent storage (Azure Disk/Files) | Additional storage cost |
| Azure Monitor / Log Analytics | Additional observability cost |
| Higher TPM capacity on Azure OpenAI | Higher potential token spend |
| Azure Reservations (1 or 3 year) | 20-40% discount on compute |

---

## Cost Monitoring

```bash
# View resource group costs for a date range
az consumption usage list \
  --start-date <YYYY-MM-DD> \
  --end-date <YYYY-MM-DD> \
  --query "[?contains(resourceGroup, '<resource-group-name>')]" \
  --output table
```

Set up budget alerts in Azure Portal: Cost Management → Budgets → Create budget with alert thresholds at meaningful percentages of your target spend.

---

## Optimization Checklist

### Before Deployment
- [ ] Verify Azure subscription has required vCPU quota
- [ ] Confirm Azure OpenAI access is approved
- [ ] Set up a budget alert in Azure Cost Management
- [ ] Choose `spot_instances = true/false` based on reliability needs

### During Use
- [ ] Monitor token usage via Azure OpenAI metrics in the Portal
- [ ] Keep conversations concise to minimize token spend
- [ ] Clear conversation context between sessions if not needed

### After Demo / Teardown
- [ ] Run `terraform destroy` to remove all resources
- [ ] Verify resource group deletion: `az group show --name <rg-name>`
- [ ] Check for orphaned resources (public IPs, disks)
- [ ] Review final charges in Azure Cost Management
