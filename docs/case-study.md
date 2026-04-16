# Case Study: Open WebUI on AKS with Azure AI Foundry

A walkthrough of the design decisions, technical challenges, and trade-offs made building this infrastructure — intended for presentation during the live deployment.

---

## Objective

Deliver a **Terraform repo** that enables a developer to spin up a working AI chat POC on Azure with minimal required inputs, in a single `terraform apply`. Emphasis on:

- Low cost (POC/demo budget)
- Minimal operational complexity
- Real security thinking, even if not fully hardened for production

---

## Architecture

```
User (Browser)
    │  HTTPS — Let's Encrypt TLS
    ↓
Azure Static Public IP  (<project_name>.<location>.cloudapp.azure.com)
    │
    ↓
Traefik  (Gateway API ingress controller)
    │  HTTPRoute → open-webui service (ClusterIP)
    ↓
Open WebUI Pod
    │  OpenAI-compatible API  →  http://litellm:4000/v1
    ↓
LiteLLM Pod  (API key read from Kubernetes Secret)
    │  Azure OpenAI REST API  (HTTPS + api-key header)
    ↓
Azure OpenAI (AI Foundry) — gpt-4o
```

### AKS Node Pools

| Pool   | Size              | Pricing  | Purpose                   |
|--------|-------------------|----------|---------------------------|
| system | Standard_DS2_v2   | Regular  | System / kube-system pods |
| user   | Standard_D2s_v3   | Spot     | Open WebUI, Traefik, cert-manager |

---

## What's Deployed

Everything is provisioned in one `terraform apply` — no manual `kubectl` or `helm` commands:

| Layer              | Component                                   | How                    |
|--------------------|---------------------------------------------|------------------------|
| Azure infra        | Resource group, AKS, Azure OpenAI           | `azurerm` provider     |
| Ingress controller | Traefik (Gateway API)                       | Helm release           |
| TLS                | cert-manager + Let's Encrypt                | Helm release + kubectl |
| Gateway            | GatewayClass, Gateway, HTTPRoute            | `kubectl` manifests    |
| API proxy          | LiteLLM (ConfigMap + Deployment + Service)  | `kubectl` manifests    |
| Auth secret        | Azure OpenAI API key                        | `kubernetes_secret`    |
| Chat app           | Open WebUI                                  | Helm release           |

---

## Key Design Decisions

### 1. LiteLLM as an API compatibility layer

**Problem:** Azure OpenAI uses a different URL structure and requires `api-version` as a query parameter. Open WebUI expects a standard OpenAI-compatible `/v1/chat/completions` endpoint. They don't speak the same dialect out of the box.

**Decision:** Deploy LiteLLM as an in-cluster proxy.

- LiteLLM exposes a standard `/v1` OpenAI-compatible endpoint to Open WebUI
- Internally it translates requests to Azure's deployment URL format and injects the required `api-version` parameter
- Model routing config is stored in a ConfigMap; the API key is injected via a Kubernetes Secret (not hardcoded in the ConfigMap or image)
- Open WebUI simply points to `http://litellm.default.svc.cluster.local:4000/v1`

**Production path:** Replace the API key + LiteLLM with Workload Identity (AKS federated credential → Entra ID token). This eliminates the long-lived secret entirely. The infrastructure scaffolding for this (OIDC issuer, user-assigned identity, federated credential, role assignment) was prototyped during development but not included in the final POC to keep the demo reliable.

---

### 2. Traefik with Gateway API (not a plain LoadBalancer Service)

**Problem:** The simplest public exposure is `Service.type = LoadBalancer` directly on Open WebUI. That works, but gives you no TLS termination, no hostname-based routing, and a dynamic IP that changes on redeploy.

**Decision:** Static public IP + Traefik + Kubernetes Gateway API + cert-manager.

- Static IP is allocated in the AKS node resource group (where the cluster identity has
  permissions) and pinned to Traefik's LoadBalancer Service
- cert-manager issues a Let's Encrypt TLS certificate for the Azure DNS FQDN
- Open WebUI is a ClusterIP service — all traffic enters via the Gateway
- HTTPRoute wires the hostname to Open WebUI with automatic HTTPS redirect

**Result:** A real, publicly accessible HTTPS endpoint with a valid certificate and a stable DNS name on the first apply.

**Trade-off:** More components, longer initial deploy. For a POC this is still worth it — it demonstrates production patterns and avoids the `kubectl port-forward` antipattern.

---

### 3. TLS with cert-manager and Let's Encrypt

cert-manager is deployed via Helm and configured with a `ClusterIssuer` pointing at the Let's Encrypt ACME server. It uses an HTTP-01 challenge — Let's Encrypt makes an HTTP request to a well-known path on the domain to verify ownership, which Traefik serves automatically.

A `Certificate` resource requests a TLS cert for the Azure DNS FQDN (`<project_name>.<location>.cloudapp.azure.com`). cert-manager stores the issued cert as a Kubernetes Secret in the `traefik` namespace, where the Gateway can reference it for TLS termination. Renewal is handled automatically before expiry.

The static public IP is what makes this work reliably — the DNS label is stable, so the HTTP-01 challenge resolves correctly on the first apply.

---

### 4. Why `gavinbunney/kubectl` for CRDs

The standard `hashicorp/kubernetes` provider validates resource schemas at plan time. CRD-based resources like `GatewayClass`, `Gateway`, and `ClusterIssuer` don't exist until their respective Helm charts install the CRDs — so the provider fails during `terraform plan`. `gavinbunney/kubectl` applies manifests the same way `kubectl apply -f` does, deferring schema validation to apply time, after CRDs exist. This is a well-known Terraform pattern for Kubernetes CRD-based resources.

---

### 4. Provider bootstrap (the chicken-and-egg problem)

The `kubernetes`, `helm`, and `kubectl` providers need the AKS cluster endpoint and certificates to connect — but those only exist after the cluster is created.

Solved with `try(..., "")` in `providers.tf`:

```hcl
provider "kubernetes" {
  host = try(module.aks.cluster_endpoint, "")
  ...
}
```

During `terraform plan`, `module.aks.cluster_endpoint` is unknown, so `try()` returns `""`.
During `terraform apply`, Terraform creates the AKS cluster first (via explicit `depends_on`
chains on all Kubernetes resources), then re-evaluates the provider configuration with real credentials before applying any Kubernetes resources.

---

## Trade-offs

| Decision | Trade-off |
|----------|-----------|
| API key in Kubernetes Secret (via LiteLLM) | Long-lived credential; production path is Workload Identity — prototyped but reverted for demo reliability |
| Single replica | No HA — acceptable for a POC demo |
| No multi-AZ node pools | Lower cost, lower resilience |
| No autoscaling | Spot eviction shuts down workloads; no HPA to reschedule |
| Spot instances (user pool) | ~90% cost savings; acceptable eviction risk for a demo |
| Free tier AKS | No SLA on control plane; fine for POC |
| No persistent storage | Open WebUI loses state on pod restart — intentional for stateless demo |
| No GitOps | Helm releases managed by Terraform; simpler but less lifecycle management |

---

## Cost

Designed for minimum viable spend:

| Component         | Config                       |
|-------------------|------------------------------|
| AKS Control Plane | Free tier                    |
| System node pool  | 1x Standard_DS2_v2 (regular) |
| User node pool    | 1x Standard_D2s_v3 (spot)   |
| Static public IP  | Standard                     |
| Azure OpenAI      | Pay-per-token, 10K TPM cap   |

The 10K TPM capacity limit on the Azure OpenAI deployment acts as a cost ceiling — it prevents runaway token spend during testing or an extended demo.

See [cost-analysis.md](cost-analysis.md) for detailed breakdown and alternative configurations.

---

## Security

### What's implemented

- **HTTPS with valid TLS** — Let's Encrypt certificate, auto-renewed by cert-manager
- **Secret not in manifests** — API key stored in a `kubernetes_secret` resource, injected into
  LiteLLM via `secretKeyRef`; not hardcoded in the ConfigMap or Helm values

### What's not implemented (and why)

| Control | Production recommendation | POC decision |
|---------|--------------------------|--------------|
| Workload Identity | No long-lived credentials | Prototyped, reverted — SDK credential chain needs live cluster to debug | Key Vault + CSI driver in production |
| Private AKS cluster | No public API endpoint | Public — required for `terraform apply` from local machine |
| Azure Private Link for OpenAI | No public OpenAI endpoint | Public — acceptable for demo |
| Network policies | Pod-to-pod traffic control | Not implemented — adds complexity |
| Observability | Azure Monitor, Log Analytics | Not implemented — POC scope |

---

## What I Would Do Differently in Production

1. **GitOps for addon lifecycle** — cert-manager, Traefik, and Open WebUI should be managed by ArgoCD or Flux, not Terraform Helm releases. Terraform is good at provisioning infrastructure; it's awkward for managing in-cluster workload upgrades.

2. **Autoscaling** — HPA on Open WebUI, KEDA or Cluster Autoscaler for node-level scaling. With spot instances and no autoscaling, a spot eviction currently causes downtime until AKS replaces the node.

3. **Multi-AZ node pools** — at minimum, zone-redundant system pool.

4. **Observability** — at minimum, Log Analytics workspace connected to AKS diagnostic settings, and Azure OpenAI metrics dashboarded.

5. **Private networking** — private AKS cluster, Azure Private Link for OpenAI, private DNS zones.

---

## Teardown

```bash
terraform destroy
```

All resources — AKS cluster, Azure OpenAI, static IP, resource group — are destroyed. The static IP lives in the AKS node resource group and is cleaned up automatically with the cluster.

Verify:

```bash
az group show --name rg-<project_name>-<environment>
# Expected: ResourceGroupNotFound
```
