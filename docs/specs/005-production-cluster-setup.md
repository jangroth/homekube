# Spec 005 — Production-Like Cluster Setup (Phase 5)

**Status:** Draft  
**Phase:** 5  
**Playbooks / Repos:** `homekube-main` (Ansible prerequisites), `homekube-apps` (ArgoCD app manifests)

---

## Problem

ArgoCD is running and `metrics-server` is healthy. The cluster has no persistent storage, no observability, and no identity management. The goal of Phase 5 is to bring the cluster to a "production-like" state: everything GitOps-managed, metrics and logs aggregated, dashboards available, and a single sign-on layer protecting cluster services.

---

## Current State

| Component | Status |
|-----------|--------|
| Kubernetes 1.36.1 | Running, 4 nodes Ready |
| Cilium 1.19.4 | Healthy |
| ArgoCD 9.5.14 | Running, root-app synced |
| metrics-server | Running, healthy |
| argocd-config | Synced (NodePort :30000) |
| kubelet CSR auto-approval | Manual bulk-approve only — breaks on cert rotation |
| Persistent storage | None |
| Load balancer | Not deployed |
| Metrics / Alerting | None |
| Log aggregation | None |
| Identity / SSO | None |

---

## Scope

### In scope

1. **kubelet-csr-approver** — auto-approve `kubernetes.io/kubelet-serving` CSRs
2. **Longhorn** — block storage CSI; NVMe-backed, 2 replicas
3. **MetalLB** — L2 load balancer for home network service exposure
4. **MinIO** — S3-compatible object store; backing store for Loki
5. **kube-prometheus-stack** — Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics
6. **Loki** — log aggregation backend (S3 via MinIO)
7. **Promtail** — DaemonSet log shipper to Loki
8. **Identity/SSO** — Dex as OIDC federation proxy; Google OAuth2 as upstream identity provider. ArgoCD and Grafana authenticate via Dex. No local user database — Google handles credentials and MFA.
9. **Service mesh** — Istio (sidecar mode); mTLS, L7 traffic management, observability. Deployed via `istioctl` or Helm; Kiali dashboard as ArgoCD app. Cilium CNI runs alongside in `veth` mode (no kube-proxy replacement conflict with Istio's iptables interception).
10. **Backups** — cluster state and persistent data backed up to external S3. Three targets: etcd snapshot (via Ansible CronJob on pi0), Longhorn volume backups (built-in Longhorn → S3), Kubernetes resource manifests (Velero → S3). External S3 bucket required (not MinIO — MinIO is on-cluster and goes down with the cluster).

### Out of scope (deferred to later phase)

- **Gateway API + Istio ingress** — Kubernetes Gateway API (`HTTPRoute`, `GatewayClass`) as the ingress layer via Istio. Preferred over traditional Ingress; deferred until Istio (wave 3) is stable.
- **DNS (Tailscale split DNS)** — in-cluster DNS server (k8s_gateway or CoreDNS) exposed via MetalLB; Tailscale split DNS routes `*.homekube.internal` to it; ExternalDNS writes records automatically. No public domain or home network exposure required. Depends on Gateway API being in place first.
- Network policies
- OPA/admission control
- Multi-tenancy

---

## Infrastructure Prerequisites (Ansible)

Before enabling apps in ArgoCD, one Ansible task must be added to `k8s-node`:

**Create `/storage` directory on every node** — Longhorn's `defaultDataPath: /storage` requires this directory to exist on the NVMe filesystem. Add to `configure_storage.yml`:

```yaml
- name: Create Longhorn storage directory
  ansible.builtin.file:
    path: /storage
    state: directory
    owner: root
    group: root
    mode: "0755"
```

Re-run `task 22-k8s-nodes` to apply before enabling Longhorn in ArgoCD.

---

## Component Details

### 1. kubelet-csr-approver

- **Helm chart:** `postfinance/kubelet-csr-approver`
- **Repo:** `https://postfinance.github.io/kubelet-csr-approver`
- **Version:** latest (check at implementation time)
- **Wave:** `-1` (wave-00-init, same as other foundation apps)
- **Config:** Approve only `kubernetes.io/kubelet-serving` signerName; restrict to cluster node IP ranges (`10.0.0.0/24`, pod CIDR `10.244.0.0/16`)
- **No storage dependency**

### 2. MetalLB

- **Helm chart:** `metallb/metallb 0.14.9` (already configured)
- **Wave:** `-1`
- **Config:** L2 mode, IP pool `192.168.86.241–192.168.86.251` (home router subnet)
- **Note:** LB IPs are on the home WiFi subnet — reachable from local network. Tailscale access still uses NodePorts or port-forward unless Tailscale subnet routing is configured (out of scope for this phase).
- **Already has ArgoCD manifest** — just needs uncommenting in kustomization.yaml

### 3. Longhorn

- **Helm chart:** `longhorn/longhorn v1.9.1` (already configured)
- **Wave:** `-1`
- **Config:** `defaultDataPath: /storage`, 2 replicas, pre-upgrade checker disabled
- **Prerequisite:** `/storage` dir must exist on all nodes (Ansible task above)
- **UI:** NodePort via longhorn-extras (wave-01); useful for monitoring replica health
- **Already has ArgoCD manifest** — needs Ansible prereq + uncommenting

### 4. MinIO

- **Helm chart:** `bitnami/minio 17.0.21` (already configured)
- **Wave:** `01`
- **Depends on:** Longhorn (PVC for MinIO data)
- **Config:** values in `wave-01-apps/minio/minio-values.yaml`
- **Buckets needed:** `loki-logs`, `loki-ruler`, `loki-admin`
- **Credentials:** currently `admin`/`admin1234` hardcoded — acceptable for home lab, document the risk
- **Already has ArgoCD manifest** — needs uncommenting

### 5. kube-prometheus-stack

- **Helm chart:** `prometheus-community/kube-prometheus-stack` (currently pinned at `79.50.0`)
- **Wave:** `01`
- **Depends on:** Longhorn (Prometheus PVC, 50Gi)
- **Exposes:** Prometheus NodePort `30002`, Grafana NodePort `30003`, Alertmanager NodePort `30004`
- **Includes:** Prometheus, Alertmanager, Grafana, node-exporter (DaemonSet), kube-state-metrics
- **Grafana datasources:** Prometheus auto-wired; Loki datasource must be added (via `additionalDataSources` in Helm values)
- **SSO integration:** Grafana OIDC config points to Dex; added to Helm values in wave 2
- **Already has ArgoCD manifest** — needs Loki datasource addition + uncommenting

### 6. Loki

- **Helm chart:** `grafana/loki 6.41.1` (already configured)
- **Wave:** `01`
- **Depends on:** MinIO (S3 backend)
- **Config:** S3 via `minio.minio.svc.cluster.local:9000`, 3 buckets, 90-day retention
- **Note:** persistence disabled (uses S3 only) — no Longhorn PVC needed for Loki itself
- **Credentials:** currently hardcoded in Application manifest — acceptable for home lab
- **Already has ArgoCD manifest** — needs uncommenting

### 7. Promtail

- **Helm chart:** `grafana/promtail` (new — not yet in homekube-apps)
- **Wave:** `01` (after Loki)
- **Depends on:** Loki
- **Config:** DaemonSet; ship all pod logs to Loki; use `loki.observability.svc.cluster.local`
- **No storage dependency**
- **Needs new ArgoCD manifest** in `wave-01-apps/`

### 8. Dex (Identity / SSO)

- **Helm chart:** `dex/dex` (from `https://charts.dexidp.io`)
- **Wave:** `02` (after all wave-01 apps are stable)
- **Depends on:** nothing (stateless; no PVC needed)
- **Exposes:** NodePort (port TBD) — redirect URI registered in Google Console
- **Config:** Google connector with client ID/secret from Kubernetes Secret; ArgoCD and Grafana registered as static OIDC clients
- **Credentials:** Google OAuth2 client ID + secret stored as a Secret (not in git); created manually as a human checkpoint before wave 2
- **Needs new ArgoCD manifest** in `wave-02-custom/` (or a new `wave-02-identity/`)

---

## Wave Structure

```
wave -1 (sync-wave: "-1")   kubelet-csr-approver  MetalLB  Longhorn  metrics-server  argocd-config
wave  1 (sync-wave: "01")   MinIO  kube-prometheus-stack  Loki  Promtail  longhorn-extras
wave  2 (sync-wave: "02")   Identity/SSO  ArgoCD OIDC config  Grafana OIDC config
wave  3 (sync-wave: "03")   Istio (istiod + ingress gateway)  Kiali dashboard  Velero
```

**Note on Istio:** Istio is installed via `istioctl` or the `base`/`istiod`/`gateway` Helm charts. The control plane (`istiod`) and ingress gateway are ArgoCD-managed. Cilium must run without kube-proxy replacement (`kubeProxyReplacement: false`) to avoid conflict with Istio's iptables interception — verify current Cilium config before enabling. Namespaces opt in to the mesh via the `istio-injection: enabled` label.

---

## Acceptance Criteria

### Foundation (wave -1)

- [ ] `kubectl get csr` shows no `Pending` entries for `kubernetes.io/kubelet-serving` within 60s of node start
- [ ] `kubectl top nodes` returns CPU/memory for all 4 nodes
- [ ] `kubectl get pods -n metallb-system` — all pods Running
- [ ] MetalLB assigns an IP to a test `type: LoadBalancer` service from the `192.168.86.241/251` pool
- [ ] `kubectl get pods -n longhorn-system` — all pods Running
- [ ] Longhorn UI accessible; all 4 nodes listed as schedulable; no disk warnings
- [ ] A `PersistentVolumeClaim` with `storageClass: longhorn` binds successfully (2-replica volume)

### Observability (wave 1)

- [ ] `kubectl get pods -n minio` — Running; MinIO console accessible
- [ ] All three Loki buckets exist in MinIO
- [ ] `kubectl get pods -n observability` — Prometheus, Grafana, Alertmanager, node-exporter (×4), kube-state-metrics all Running
- [ ] Grafana UI accessible at `:30003`; Prometheus datasource shows green; Loki datasource shows green
- [ ] `kubectl get pods -n observability -l app=promtail` — one pod per node (DaemonSet), all Running
- [ ] Loki receives logs: Grafana → Explore → Loki → `{namespace="kube-system"}` returns entries
- [ ] Prometheus scraping cluster metrics: `kubectl --namespace observability port-forward svc/prometheus-operated 9090` → Targets page shows all targets Up
- [ ] Node-exporter dashboard visible in Grafana (pre-built dashboard 1860 or similar)
- [ ] Longhorn dashboard visible in Grafana

### Identity / SSO (wave 2)

- [ ] SSO UI accessible and login works
- [ ] ArgoCD login via SSO (OIDC redirect works end-to-end)
- [ ] Grafana login via SSO (OIDC redirect works end-to-end)
- [ ] Kubernetes API accessible via OIDC token (optional, see Open Questions)

### Service Mesh (wave 3)

- [ ] `kubectl get pods -n istio-system` — istiod and ingress gateway Running
- [ ] Kiali UI accessible; service graph renders cluster traffic
- [ ] mTLS enforced in at least one test namespace (PeerAuthentication `STRICT` mode)
- [ ] Existing cluster traffic unaffected after mesh activation (all wave-1 apps still healthy)
- [ ] Cilium CNI compatibility confirmed — no iptables conflicts, pod networking healthy

### Backups (wave 3)

- [ ] External S3 bucket provisioned and credentials stored as a Kubernetes Secret
- [ ] Longhorn backup target configured (S3 endpoint + bucket in Longhorn settings); test backup of one volume completes
- [ ] Velero installed and connected to S3; `velero backup create smoke-test` completes successfully
- [ ] etcd snapshot CronJob running on pi0 (daily); snapshot uploaded to S3; verify restore procedure documented
- [ ] Longhorn scheduled backups enabled (daily, retain 7)

---

## Open Questions

### OQ-1: Identity / SSO solution — DECIDED

**Dex + Google OIDC.**

Dex acts as an OIDC federation proxy; Google is the upstream identity provider. ArgoCD and Grafana are configured as Dex OIDC clients. Users authenticate with their Google account.

**Prerequisites before deploying:**
- Create a Google OAuth2 client ID + secret in Google Cloud Console (Credentials → OAuth 2.0 Client ID, type: Web application)
- Redirect URI: `http://<dex-host>/callback` — must be registered in Google Console
- Store client ID and secret as a Kubernetes Secret (not in git)

**Constraints to be aware of:**
- No local user management — everyone needs a Google account
- Group-based RBAC requires Google Workspace; free accounts expose email/profile only
- Dex has no admin UI — configured entirely via Helm values

### OQ-2: Access strategy

SSO (and a polished cluster experience) requires stable service hostnames for OIDC redirect URIs.

**Decided:**
- **Ingress layer:** Kubernetes Gateway API (`GatewayClass`, `Gateway`, `HTTPRoute`) via Istio — preferred over traditional Ingress, deferred until wave 3 Istio is stable.
- **DNS:** Tailscale split DNS with in-cluster DNS server (`k8s_gateway`) exposed via MetalLB. Domain `homekube.internal` resolves on all Tailscale devices; no public exposure. Deferred until Gateway API is in place.
- **Tailscale subnet routing:** Enable on pi0 to give darth direct access to MetalLB LB IPs (`192.168.86.x`) as a bridge until full DNS is wired up.

**For this phase (wave 1–2):** services remain on NodePort. SSO redirect URIs will use `http://piN:PORT` format temporarily.

### OQ-3: External S3 provider for backups — DECIDED

**AWS S3.** First-class support in both Velero and Longhorn. AWS credentials stored as Kubernetes Secrets (not in git). Bucket and IAM user/policy created as a human checkpoint before wave 3.

### OQ-4: Grafana timezone — DECIDED

**Australia/Sydney.** Already set in current Helm values — no change needed.

---

## Deployment Order

1. **Ansible prerequisite:** add `/storage` dir task → run `task 22-k8s-nodes`
2. **Wave -1:** enable in kustomization: `kubelet-csr-approver`, `metallb`, `longhorn` (already have manifests for metallb and longhorn; new manifest needed for csr-approver)
3. **Validate wave -1** (acceptance criteria above)
4. **Wave 1:** enable `minio`, `longhorn-extras`, `kube-prometheus-stack`, `loki`; create new `promtail` manifest
5. **Validate wave 1**
6. **Wave 2:** implement chosen SSO solution; update ArgoCD + Grafana OIDC config
7. **Validate wave 2**
