# Spec 005 — Production-Like Cluster Setup (Phase 5)

**Status:** Draft
**Phase:** 5
**Repos:** `homekube-main` (Ansible prerequisites), `homekube-apps` (ArgoCD app manifests)

---

## Problem

ArgoCD and `metrics-server` are running. The cluster has no persistent storage, no service exposure beyond NodePorts, no observability, no identity layer, and no backups. The goal of Phase 5 is to bring the cluster to a "production-like" state organised around the capabilities it exposes to its users — not around individual Helm charts.

---

## Current State

| Component | Status |
|-----------|--------|
| Kubernetes 1.36.1 | Running, 4 nodes Ready (single control plane on pi0) |
| Cilium 1.19.4 | Healthy |
| ArgoCD 9.5.15 | Running, root-app synced |
| metrics-server | Running, healthy |
| argocd-config | Synced (NodePort :30000) |
| Ansible prerequisites | `/storage` (NVMe-backed) on all 4 nodes; `open-iscsi` present |
| kubelet CSR auto-approval | Manual bulk-approve only — breaks on cert rotation |
| Secrets management | sealed-secrets 2.18.6 deployed + validated (cert saved, round-trip passed) |
| Internal TLS | None — no CA, no cert automation |
| Persistent storage | None |
| Load balancer | Not deployed |
| Metrics / Alerting | None |
| Log aggregation | None |
| Identity / SSO | None |
| Backups | None — pi0 control plane is a single point of failure |

---

## Architectural Notes

A few decisions that cut across multiple capabilities, called out here so they aren't repeated below.

- **Single control plane (pi0) accepted as SPOF.** No stacked-etcd HA in this phase. Mitigation is an etcd-snapshot job running on pi0 from day one (see Infrastructure Prerequisites), uploading to external S3. Restore is manual and documented.
- **MetalLB LB traffic rides Wi-Fi.** The L2 pool sits on the home Wi-Fi subnet (`192.168.86.0/24`), so LB ARP responses egress on `wlan0`. Inter-node and etcd traffic stays on the wired switch (`10.0.0.0/24`). Documented explicitly so it doesn't read as a misconfig.
- **Secrets in git use `sealed-secrets`.** No plaintext credentials in any repo. `kubeseal` is the only path to commit a Secret.
- **Internal TLS via cert-manager** with a self-signed cluster issuer. Lets ArgoCD, Grafana, and Dex serve OIDC over HTTPS before public DNS lands.
- **ARM64 image pre-flight.** Before enabling any wave, verify each Helm chart's images resolve for `linux/arm64`:
  ```sh
  crane manifest --platform linux/arm64 <image:tag>
  ```
  This catches Bitnami licensing surprises and any chart that ships AMD64-only init containers.

---

## Version Policy

**Track the latest upstream GA release for every component.** No release candidates, betas, alphas, or `*-pre.*` builds in any wave. Patch and minor bumps applied as they ship; major bumps reviewed for breaking changes against current Helm values, then applied promptly — running on N-2 is not a goal of this lab. Renovate (or equivalent) runs against `homekube-apps` to surface chart-version PRs; merges flow through ArgoCD like any other change.

The table below is the source of truth for what is pinned at spec time. Inline mentions in capability sections must match this table; if they drift, this table wins. Re-verify before each implementation session — versions older than ~30 days are stale by definition.

### Pinned Versions (verified 2026-06-23)

Chart version is the `targetRevision` used in ArgoCD manifests. App version is what runs in the cluster.

| Component | Chart Version | App Version | Notes |
|---|---|---|---|
| Kubernetes | 1.36.1 | 1.36.1 | already installed via kubeadm |
| Cilium | 1.19.4 | 1.19.4 | already installed; 1.20 still pre-release |
| ArgoCD | 9.5.15 | v3.4.2 | argo Helm repo |
| sealed-secrets | 2.18.6 | 0.37.0 | `bitnami-labs/sealed-secrets` |
| cert-manager | v1.20.2 | v1.20.2 | jetstack |
| kubelet-csr-approver | 1.2.14 | v1.2.14 | postfinance |
| MetalLB | 0.16.0 | v0.16.0 | |
| Longhorn | 1.11.2 | v1.11.2 | |
| MinIO | — | `RELEASE.2025-10-15T17-29-55Z` | upstream chart, not Bitnami; version is image tag |
| Loki | 7.0.0 | 3.6.7 | **chart v7 is a major bump**: values schema differs from v6; fresh install only |
| kube-prometheus-stack | 87.0.1 | v0.92.0 | bumped from 85.3.0; review changelog before applying (2-chart-version jump) |
| Grafana Alloy | 1.8.1 | v1.16.1 | replaces Promtail |
| Dex | 0.24.0 | 2.44.0 | dexidp |
| Istio | 1.30.0 | 1.30.0 | istioctl install + helm |
| Velero | 12.0.1 | 1.18.0 | with CSI snapshot plugin + `velero-plugin-for-aws` |

---

## Capabilities

Phase 5 introduces eleven capabilities. Each maps to a sync-wave for ArgoCD execution, but the spec is organised by capability so dependencies and intent are explicit. Wave numbers are an execution detail, not a structural one.

| # | Capability | Wave |
|---|------------|------|
| 1 | Secrets Management (sealed-secrets) | `-1` |
| 2 | Internal TLS (cert-manager) | `-1` |
| 3 | Node Hygiene (CSR auto-approval) | `-1` |
| 4 | Service Exposure (L4 LB) | `-1` |
| 5 | Block Storage | `-1` |
| 6 | Metrics | `01` |
| 7 | Logs (incl. internal Object Storage) | `01` |
| 8 | Dashboards & Alerting | `01` |
| 9 | Identity & SSO | `02` |
| 10 | Service Mesh | `03` |
| 11 | Backups & DR | `03` |

---

### 1. Secrets Management — sealed-secrets

**Purpose:** Allow Kubernetes Secrets to be committed to git as ciphertext. Lands first because every subsequent capability that touches credentials (MinIO, OIDC, Alertmanager Telegram, S3 backups) depends on it.

**Wave:** `-1`

**Components:**
- Helm chart `bitnami-labs/sealed-secrets` — app `0.37.0` (upstream maintainer repo, not the deprecated Bitnami catalog)
- `kubeseal` CLI on darth, matched to the controller version

**Depends on:** nothing.

**Constraints & decisions:**
- Controller key is generated on first install and **backed up out-of-band** (kubeseal `--fetch-cert` saved to a password manager) so re-installs can decrypt existing sealed secrets.
- Cluster-wide scope (`--scope cluster-wide`) is *not* used — secrets are sealed per namespace.

**Acceptance:**
- [x] `sealed-secrets-controller` pod Running in `kube-system`
- [x] `kubeseal --fetch-cert` returns the public cert; cert saved to password manager
- [x] Round-trip test: create a Secret → `kubeseal` → apply → controller materialises the original Secret

---

### 2. Internal TLS — cert-manager

**Purpose:** Provide certificates for in-cluster services (ArgoCD, Grafana, Dex) so OIDC and any HTTPS-only client behaves correctly before public DNS exists. Lays the groundwork for ACME issuance later (out of scope this phase).

**Wave:** `-1`

**Components:**
- Helm chart `jetstack/cert-manager` — app `1.20.2`
- A `ClusterIssuer` named `homekube-ca` backed by a self-signed root, with `Certificate` resources for each consuming service

**Depends on:** nothing.

**Constraints & decisions:**
- Self-signed root CA — public ACME is deferred with DNS. The root CA cert is exported and trusted on darth so browsers don't warn.
- One `ClusterIssuer` for the whole cluster; no per-namespace issuers in this phase.
- `homekube-ca-secret` (cert + private key) is **backed up out-of-band** to the password manager — same reasoning as the sealed-secrets key. If cert-manager is reinstalled and the secret is lost, all previously-issued certificates become unverifiable. On reinstall, restore the secret before ArgoCD syncs `cert-manager-config` so cert-manager adopts the existing key pair instead of generating a new one:
  ```sh
  # Export (do once, store in password manager):
  kubectl get secret homekube-ca-secret -n cert-manager -o yaml > homekube-ca-secret.yaml
  # Restore (before cert-manager-config syncs on reinstall):
  kubectl apply -f homekube-ca-secret.yaml
  ```

**Acceptance:**
- [x] `cert-manager`, `cainjector`, `webhook` pods Running
- [x] `ClusterIssuer/homekube-ca` reports `Ready=True`
- [x] A test `Certificate` issues and the secret is populated
- [x] Root CA cert exported and trusted on darth (`sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain homekube-ca.crt`)
- [x] `homekube-ca-secret` (full secret YAML, cert + key) saved to password manager

---

### 3. Node Hygiene — CSR auto-approval

**Purpose:** Automatically approve `kubernetes.io/kubelet-serving` CSRs so kubelet certificate rotation does not require manual `kubectl certificate approve` runs. Today CSRs are bulk-approved by hand; this breaks silently when certificates rotate (default 1 year).

**Wave:** `-1`

**Components:**
- Helm chart `postfinance/kubelet-csr-approver` — app `1.2.14` (re-verify against upstream at install time per Version Policy)
- Repo: `https://postfinance.github.io/kubelet-csr-approver`

**Depends on:** nothing.

**Constraints & decisions:**
- Approve only the `kubernetes.io/kubelet-serving` signer.
- Restrict to node IP ranges: `10.0.0.0/24` (switch) and the cluster pod CIDR.
- **Verify pod CIDR before pinning** — confirm against the live Cilium config:
  ```sh
  kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.cluster-pool-ipv4-cidr}'
  ```
  Do not assume the kubeadm default `10.244.0.0/16`.

**Acceptance:**
- [x] `kubectl get csr` shows no `Pending` entries for `kubernetes.io/kubelet-serving` within 60s of any node start
- [x] CSRs from outside the allowed CIDRs are not approved

---

### 4. Service Exposure — L4 Load Balancer

> ⚠️ **Superseded by spec 006.** The MetalLB approach below announces correctly but LB IPs are
> **not actually reachable** — Cilium's eBPF DNAT only attaches to `eth0`, and adding `wlan0`
> conflicts with MetalLB's VIPs (DECISION-030). The acceptance boxes were checked optimistically;
> treat them as **not met**. Replacement: Cilium-native LB-IPAM + L2 announcements — see
> `docs/specs/006-cilium-native-loadbalancer.md` and DECISION-031. The section below is retained
> as the historical record of the MetalLB design.

**Purpose:** Allocate routable IPs to `type: LoadBalancer` services. Removes the NodePort-only constraint and is a prerequisite for any sensible ingress story later (Gateway API in a future phase).

**Wave:** `-1`

**Components:**
- Helm chart `metallb/metallb 0.16.0` (manifest already exists — bump from 0.14.9 per Version Policy)
- `IPAddressPool` and `L2Advertisement` CRDs
- Tailscale subnet route on **all 4 nodes** advertising `192.168.86.240/28` (covers the MetalLB pool; Tailscale auto-selects best path and fails over)

**Depends on:** nothing.

**Constraints & decisions:**
- L2 mode, IP pool `192.168.86.241–192.168.86.251` (home Wi-Fi subnet). LB ARP responses egress on `wlan0` — documented and accepted; inter-node and etcd traffic remain on the wired switch.
- `L2Advertisement` pinned to pi1/pi2/pi3 (worker nodes only) to keep failover deterministic and avoid GARP storms across all four interfaces.
- **Tailscale subnet routing on pi0** makes LB IPs reachable from `darth` regardless of network:
  - IP forwarding (`net.ipv4.ip_forward=1`) already enabled on all nodes via existing k8s sysctl config — no change needed
  - `tailscale set --advertise-routes=192.168.86.240/28` on **all 4 nodes** via Ansible; Tailscale auto-selects best path and fails over if a node goes down
  - Approve all 4 routes in the Tailscale admin console (human step — one click per node)
  - Traffic path: darth → `tailscale0` on any node → kernel routes to `wlan0` → MetalLB IP. Cilium is configured with `devices: eth0,wlan0` so TCX programs are attached to both interfaces; wlan0 traffic is DNAT'd correctly (see DECISION-030).
  - Advertising only `/28` (not the full `/24`) limits exposure to the MetalLB pool; home devices (router, NAS etc.) remain unreachable from Tailscale unless explicitly widened later.
- Standard going forward: new user-facing services use `type: LoadBalancer`; NodePorts kept only for existing services until they're migrated.

**Acceptance:**
- [x] `kubectl get pods -n metallb-system` — all pods Running
- [x] A test `type: LoadBalancer` service receives an IP from `192.168.86.241–251`
- [x] LB IP is reachable from a host on the home Wi-Fi network
- [x] `L2Advertisement` only advertises from the configured node set (pi1/pi2/pi3)
- [x] LB IP is reachable from `darth` over Tailscale (away from home Wi-Fi)

---

### 5. Block Storage

**Purpose:** Provide a CSI-backed `StorageClass` so workloads can request PersistentVolumeClaims. Required by Metrics (Prometheus PVC) and Logs (MinIO PVC).

**Wave:** `-1`

**Components:**
- Helm chart `longhorn/longhorn v1.11.2` (manifest already exists — bump from 1.9.1 per Version Policy)
- `longhorn-extras` (NodePort UI) — wave `01`

**Depends on:** Ansible prerequisites — `/storage` directory and `open-iscsi` userspace tooling on every node (see Infrastructure Prerequisites below).

**Constraints & decisions:**
- `defaultDataPath: /storage` (NVMe-backed).
- 2 replicas; pre-upgrade checker disabled.
- UI exposed via NodePort by `longhorn-extras` — useful for replica-health monitoring.
- `PodDisruptionBudget` for `longhorn-manager` (minAvailable: 3 of 4) so drains don't take the CSI driver offline.

**Acceptance:**
- [x] `kubectl get pods -n longhorn-system` — all pods Running
- [x] Longhorn UI lists 3 worker nodes (pi1/pi2/pi3) as schedulable; no disk warnings. pi0 is intentionally excluded — it runs etcd and is the control-plane SPOF; mixing storage I/O with etcd on the same NVMe risks latency spikes, and a pi0 reboot would degrade every volume that had a replica there.
- [x] A PVC with `storageClass: longhorn` binds and is writable from a test pod (2-replica volume)
- [x] `iscsid` running on all nodes (Ansible verifies)

---

### 6. Metrics

**Purpose:** Time-series metrics collection, storage, and alerting backbone for the cluster. Provides the data plane that Dashboards & Alerting consume.

**Wave:** `01`

**Components (from `kube-prometheus-stack 85.3.0`):**
- Prometheus (PVC: 50 Gi on Longhorn)
- Alertmanager
- node-exporter (DaemonSet, one per node)
- kube-state-metrics

> Note: Grafana ships in the same Helm chart but is treated as part of **Dashboards & Alerting** (capability 8) so it can be reasoned about independently.

**Depends on:** Block Storage (Prometheus PVC); sealed-secrets (for the Alertmanager Telegram token, configured in capability 8).

**Constraints & decisions:**
- Tracks latest GA per Version Policy; pin is `87.0.1` at spec time. Major bumps (e.g. CRD changes) get a brief review against current Helm values, then ship.
- `grafana.enabled: false` — Grafana is intentionally disabled in this chart deployment. It is enabled and configured in capability 8 (Dashboards & Alerting) where its datasources, OIDC, and NodePort are all wired up together.
- Prometheus retention: `retention: 15d`, `retentionSize: 40GiB` (gives headroom under the 50 Gi PVC; prevents WAL-fills).
- `nodeAffinity` keeps Prometheus and Alertmanager off `pi0` so the control plane isn't competing with metrics ingest.
- `PodDisruptionBudget` for Prometheus and Alertmanager (`maxUnavailable: 0` — single-replica services). Note: this blocks `kubectl drain` on the node Prometheus is running on; delete the pod first or temporarily remove the PDB before any planned node maintenance.
- **No LoadBalancer IP for Prometheus or Alertmanager.** Both are internal infrastructure; Grafana (capability 8) is the external entry point for observability. LB IPs are reserved for user-facing services.
- Prometheus exposed on NodePort `:30002` for occasional target inspection and ad-hoc PromQL queries. `kubectl port-forward` is the preferred path for deeper debugging.
- Alertmanager exposed on NodePort `:30004` for silence management.
- Resource requests/limits set explicitly (see Resource Budget table below).
- Manifest already exists; needs `additionalDataSources` (Loki) added and uncommenting in `kustomization.yaml`.

**Acceptance:**
- [x] `kubectl get pods -n observability` — Prometheus, Alertmanager, node-exporter (×4), kube-state-metrics all Running
- [x] Prometheus port-forward → Targets page shows all targets Up (all 28 incl. controller-manager, scheduler, etcd after bind-address fix)
- [x] Alertmanager UI reachable on NodePort `:30004`
- [x] Prometheus NodePort `:30002` returns query results for a basic cluster metric (e.g. `up`)
- [x] Retention settings visible in Prometheus `/status/runtimeinfo` (`15d or 40GiB`)

---

### 7. Logs

**Purpose:** Aggregate pod and node logs into a searchable backend so Grafana can run queries across the cluster.

**Wave:** `01`

**Components:**
- Helm chart `grafana/loki 7.0.0` (Loki backend) — manifest needs refresh; **single-binary mode** (`deploymentMode: SingleBinary`) — lowest memory ceiling, sufficient for home-lab cardinality. **Chart v7 is a major bump from v6** — values schema changed; do not lift v6 values blindly.
- Helm chart `grafana/alloy` (DaemonSet log shipper) — **new manifest** under `wave-01-apps/`; chart `1.8.x` (latest at install per Version Policy). Replaces Promtail, which is in feature-frozen maintenance.

#### Sub-capability: Object Storage (MinIO)

Loki needs S3-compatible object storage. MinIO runs in-cluster and exists solely to back Loki — it is not a user-facing capability, but rolls out as part of this wave because Logs cannot function without it.

- Helm chart: `minio/minio` upstream operator-less chart (vanilla deployment). **Bitnami's catalog is not used** — most Bitnami images moved to a paid registry in 2025; the upstream chart is multi-arch and unaffected.
- Image: `quay.io/minio/minio:RELEASE.2025-10-15T17-29-55Z` (latest GA per Version Policy; security release).
- Pre-flight: `crane manifest --platform linux/arm64 quay.io/minio/minio:RELEASE.2025-10-15T17-29-55Z` before enabling.
- Wave `01` (deploys before Loki)
- Buckets: `loki-logs`, `loki-ruler`, `loki-admin`
- Credentials: generated locally, stored as a **sealed-secret** committed to git (`minio-root-credentials`). No plaintext credentials in any manifest.

**Depends on:** Block Storage (MinIO PVC); Secrets Management (sealed-secret for MinIO root creds). Loki has persistence disabled and uses S3 only — no PVC for Loki itself.

**Constraints & decisions:**
- Loki S3 endpoint: `minio.minio.svc.cluster.local:9000`
- Retention: 90 days
- Alloy target: `loki.observability.svc.cluster.local`
- Loki single-binary mode chosen explicitly over SimpleScalable (3-component) — fewer pods, lower RAM, fine for projected cardinality.

**Acceptance:**
- [ ] MinIO pods Running; console reachable; three Loki buckets exist
- [ ] Loki pod Running; ready endpoint healthy
- [ ] Alloy DaemonSet — one pod per node, all Running
- [ ] LogQL query via Grafana Explore returns entries for `{namespace="kube-system"}`
- [ ] No plaintext credentials in any committed manifest (grep check)

---

### 8. Dashboards & Alerting

**Purpose:** Human-facing window onto the metrics and logs. Pre-built dashboards for nodes, cluster, and Longhorn; Alertmanager UI for active alerts; alert delivery to Telegram.

**Wave:** `01`

**Components:**
- Grafana (bundled with `kube-prometheus-stack`)
- Alertmanager UI (already counted in Metrics; included here as the alert frontend)
- **Telegram receiver** wired into Alertmanager configuration

**Depends on:** Metrics (Prometheus datasource), Logs (Loki datasource), Secrets Management (Telegram bot token as sealed-secret), Internal TLS (Grafana serving over HTTPS via cert-manager).

**Constraints & decisions:**
- Datasources: Prometheus auto-wired by the chart; Loki added via `additionalDataSources` in Helm values.
- Timezone: `Australia/Sydney` (already set in current Helm values).
- OIDC config (SSO) is added in wave `02` once Dex is up — not in this capability's scope.
- NodePort `:30003` retained; LB IP added once MetalLB is validated.
- Telegram bot created out-of-band; bot token + target chat ID stored as a sealed-secret (`alertmanager-telegram`). Alertmanager `receivers:` config references it via `bot_token_file`.
- Default route: all alerts → Telegram. Severity-based routing can be added later.

**Acceptance:**
- [ ] Grafana reachable on `:30003` (and via MetalLB LB IP); Prometheus and Loki datasources both green
- [ ] Pre-built node-exporter dashboard (1860 or similar) renders for all 4 nodes
- [ ] Longhorn dashboard renders; volume metrics populated
- [ ] Alertmanager UI reachable; default cluster alerts visible (firing or pending)
- [ ] Test alert (silenced rule + manual fire) reaches the Telegram chat
- [ ] Grafana serves a valid cert from `homekube-ca`

---

### 9. Identity & SSO

**Purpose:** Single sign-on for cluster web UIs (ArgoCD, Grafana). Removes per-app local credentials; centralises authentication on Google accounts (with MFA already enforced upstream).

**Wave:** `02`

**Components:**
- Helm chart `dex/dex` (`https://charts.dexidp.io`) — chart `0.24.0`, app `2.44.0`
- ArgoCD OIDC client config (update to `argocd-config`)
- Grafana OIDC config (update to `kube-prometheus-stack` Helm values)

**Depends on:** human checkpoint — Google OAuth2 client ID + secret created in Google Cloud Console (Credentials → OAuth 2.0 Client ID, type Web). Stored as a **sealed-secret** (`dex-google-oauth`); never plaintext. Also depends on Internal TLS (Dex must be HTTPS for OIDC clients to behave).

**Constraints & decisions:**
- Federation only — no local user database. Everyone needs a Google account.
- Group-based RBAC requires Google Workspace; free Google accounts only expose email/profile.
- Dex has no admin UI; configured entirely via Helm values.
- **OIDC redirect URIs need stable hostnames.** DNS + Gateway API are deferred (see Deferred section below). For this phase, redirect URIs use `https://piN:PORT` (TLS via `homekube-ca`) — this means OIDC config will need re-writing once DNS lands. Acknowledged churn cost.
- Tailscale subnet routing on `pi0` is the interim bridge for `darth` to reach `:30000`/`:30003` from outside the home network.

**Acceptance:**
- [ ] Dex pod(s) Running; reachable on its NodePort over HTTPS
- [ ] Dex cert issued by `homekube-ca`; clients accept it
- [ ] ArgoCD login via Google OIDC completes end-to-end (logout → re-login → roles applied)
- [ ] Grafana login via Google OIDC completes end-to-end
- [ ] (Optional) Kubernetes API accessible via OIDC token — deferred unless trivially configurable

---

### 10. Service Mesh

**Purpose:** mTLS between workloads, L7 traffic management, and a service-graph view of cluster traffic. Lays the foundation for Gateway API ingress (deferred).

**Wave:** `03`

**Components:**
- Istio control plane (`istiod`) and ingress gateway via `istioctl` or `base`/`istiod`/`gateway` Helm charts — app `1.30.0`
- Kiali dashboard (ArgoCD app — latest GA at install per Version Policy)

**Depends on:** all wave-`01` apps stable; Cilium running **without** kube-proxy replacement (`kubeProxyReplacement: false`) to avoid iptables conflict with Istio's sidecar interception.

**Constraints & decisions:**
- **The Cilium `kubeProxyReplacement` flip is a separate, scheduled change with its own rollback plan** — not folded into the mesh install. Verify current setting first; if `true`, plan a maintenance window, change, reconcile, and validate before any Istio work begins. Capture as a DECISIONS.md entry.
- **Sidecar injection is opt-in per namespace only** — `istio-injection: enabled` label on a small set of test namespaces first. No global enablement. Cluster-wide injection would consume ~80–120 MiB per pod in sidecar overhead, which is not affordable on 4×8 GiB.
- Sidecar mode (not ambient) — well-trodden path; ambient still maturing on ARM.
- Verify all Istio images are multi-arch for `linux/arm64` before install.

**Acceptance:**
- [ ] `kubectl get pods -n istio-system` — istiod and ingress gateway Running
- [ ] Kiali UI reachable; service graph renders cluster traffic
- [ ] mTLS enforced in at least one test namespace (PeerAuthentication `STRICT`)
- [ ] All wave-`01` apps still healthy post-mesh activation (regression check)
- [ ] No namespace outside the opt-in set has sidecars injected

---

### 11. Backups & DR

**Purpose:** Survive cluster loss. Three orthogonal targets: cluster state (etcd), persistent data (Longhorn volumes), Kubernetes resource manifests (Velero). External S3 only — MinIO is on-cluster and goes down with the cluster.

**Wave:** `03`

> **Note:** The etcd snapshot job is *not* in wave 3 — it lands in wave `-1` via Ansible because pi0 is a single point of failure and backup must exist before any stateful workload runs. See Infrastructure Prerequisites.

**Components (wave 3):**
- Longhorn → S3 backup target (built-in Longhorn backups)
- Helm chart `vmware-tanzu/velero` — chart `12.0.1`, app `1.18.0` — with the **CSI snapshot plugin** + `velero-plugin-for-aws` → S3
- AWS credentials stored as a **sealed-secret** (`velero-aws-credentials`)

**Depends on:** human checkpoint — AWS S3 bucket provisioned, IAM user/policy created, credentials sealed. Plus Secrets Management (capability 1) and Block Storage (capability 5).

**Constraints & decisions:**
- Backend: AWS S3 (first-class in Velero and Longhorn).
- AWS credentials sealed into git; never plaintext.
- Velero uses the **CSI snapshotter** (Longhorn supports CSI snapshots) for volume backups, not Restic/Kopia file-walking — faster and consistent at the volume level.
- Pre-flight: confirm `velero-plugin-for-aws` ships an `arm64` image; same for Kopia/Restic init containers if enabled as fallback.

**Acceptance:**
- [ ] External S3 bucket provisioned; credentials sealed and applied as a Secret
- [ ] Longhorn backup target configured; one volume backup completes successfully
- [ ] Velero installed with CSI plugin; `velero backup create smoke-test --include-namespaces test` completes successfully and includes PV data
- [ ] etcd snapshot job (from Ansible) is producing daily uploads to S3 (already running since wave `-1`)
- [ ] Restore drill: documented procedure for `etcdctl snapshot restore` on a rebuilt pi0
- [ ] Longhorn scheduled backups enabled (daily, retain 7)

---

## Resource Budget

Rough RAM allocation, sized for 4×8 GiB = 32 GiB total. Numbers are `requests`; `limits` set 1.5–2× for burst headroom. System reserved (kubelet/containerd/Cilium/CoreDNS/sealed-secrets/cert-manager) ≈ 1 GiB/node = 4 GiB. Anything above is workload budget.

| Capability | Component | RAM request | Notes |
|---|---|---|---|
| 1 | sealed-secrets controller | 64 MiB | |
| 2 | cert-manager (3 pods) | 256 MiB | |
| 3 | kubelet-csr-approver | 64 MiB | |
| 4 | MetalLB (controller + speakers ×4) | 256 MiB | |
| 5 | Longhorn (manager+driver+engines, all nodes) | 1.5 GiB | grows with attached volumes |
| 6 | Prometheus | 2 GiB | retention 15d / 40 GiB |
| 6 | Alertmanager | 128 MiB | |
| 6 | kube-state-metrics | 128 MiB | |
| 6 | node-exporter ×4 | 256 MiB | |
| 7 | MinIO | 512 MiB | single replica |
| 7 | Loki (single-binary) | 1 GiB | |
| 7 | Alloy ×4 | 512 MiB | |
| 8 | Grafana | 256 MiB | |
| 9 | Dex | 128 MiB | |
| 10 | Istio (istiod + gateway, no sidecars) | 1 GiB | sidecars budgeted per opt-in namespace |
| 11 | Velero | 256 MiB | |
| — | **Subtotal (workload)** | **~8.4 GiB** | |
| — | System reserved (4 nodes) | ~4 GiB | |
| — | Headroom / app workloads | ~19 GiB | comfortable |

Sidecar overhead is *not* in the subtotal — each opted-in namespace adds ~80–120 MiB per pod. Audit before enabling injection in a busy namespace.

---

## Infrastructure Prerequisites (Ansible)

Before enabling wave `-1` apps, extend the `k8s-node` role:

**1. Create `/storage` directory on every node** — Longhorn's `defaultDataPath: /storage` requires this directory to exist on the NVMe filesystem. Add to `configure_storage.yml`:

```yaml
- name: Create Longhorn storage directory
  ansible.builtin.file:
    path: /storage
    state: directory
    owner: root
    group: root
    mode: "0755"
```

**2. Install and enable `open-iscsi`** — Longhorn requires the iSCSI initiator userspace and a running `iscsid`. Add to `configure_storage.yml`:

```yaml
- name: Install open-iscsi
  ansible.builtin.apt:
    name: open-iscsi
    state: present

- name: Enable and start iscsid
  ansible.builtin.systemd:
    name: iscsid
    enabled: true
    state: started
```

**3. etcd snapshot job on pi0** — runs from wave `-1`, not wave 3, because pi0 is a single point of failure and DR must exist before stateful workloads. Implementation: a systemd timer on pi0 that calls `etcdctl snapshot save` and uploads to S3 via `aws s3 cp`. AWS credentials read from a root-only file populated by Ansible from a vault-stored variable.

- Schedule: daily at 03:00 local
- Retention: 14 days in S3 (lifecycle rule on the bucket)
- Snapshot also written locally to `/var/lib/etcd-backup/` (keep last 7)
- Restore procedure documented in `homekube-main/docs/restore-etcd.md`

Re-run `task 22-k8s-nodes` to apply prerequisites 1 and 2 before enabling Longhorn in ArgoCD. The etcd timer is in its own play and lands as part of the same task run.

---

## Deferred (out of scope for Phase 5)

Capabilities deliberately pushed to a later phase. Tracked here so the boundaries of Phase 5 are explicit.

- **Gateway API + Istio ingress** — Kubernetes Gateway API (`HTTPRoute`, `GatewayClass`) as the ingress layer via Istio. Preferred over traditional Ingress. Deferred until Service Mesh is stable.
- **DNS (Tailscale split DNS)** — in-cluster DNS server (`k8s_gateway` or CoreDNS) exposed via MetalLB; Tailscale split DNS routes `*.homekube.internal` to it; ExternalDNS writes records. No public domain. Depends on Gateway API being in place first. Until then, SSO redirect URIs use `https://piN:PORT` with the `homekube-ca` cert.
- **Public ACME / Let's Encrypt** — once DNS lands, swap the self-signed `ClusterIssuer` for an ACME issuer. cert-manager is already in place; only the issuer changes.
- **Stacked-etcd control-plane HA** — promote pi1/pi2 to control plane for a 3-node quorum. Deferred; relying on backups instead.
- **Network policies**
- **OPA / admission control**
- **Multi-tenancy**

---

## Rollout Order

```
Ansible    /storage · open-iscsi · etcd snapshot timer (pi0)
            ↓
wave -1   Secrets Mgmt (sealed-secrets) · Internal TLS (cert-manager)
          Node Hygiene · Service Exposure (MetalLB) · Block Storage (Longhorn)
            ↓
wave  1   Metrics (Prom/AM/node-exp/KSM) · Logs (MinIO → Loki → Alloy) · Dashboards (Grafana + Telegram)
            ↓
wave  2   Identity & SSO (Dex)  →  re-wire ArgoCD + Grafana OIDC
            ↓
wave  3   Service Mesh (Istio + Kiali) · Backups & DR (Longhorn + Velero)
```

Order within a wave is enforced by ArgoCD sync-wave + dependency annotations where needed (e.g. sealed-secrets before MinIO sealed cred; MinIO before Loki).

### Step-by-step deployment

1. **Ansible prerequisites** — `/storage`, `open-iscsi`, etcd snapshot timer → run `task 22-k8s-nodes` and verify the first etcd snapshot lands in S3
2. **Wave -1** — enable in kustomization, in this order: `sealed-secrets`, `cert-manager` (+ `ClusterIssuer/homekube-ca`), `kubelet-csr-approver`, `metallb`, `longhorn`
3. **Validate wave -1** (acceptance criteria for capabilities 1–5)
4. **Wave 1** — seal MinIO + Telegram credentials → enable `minio`, `longhorn-extras`, `kube-prometheus-stack`, `loki`; create `alloy` manifest
5. **Validate wave 1** (capabilities 6–8)
6. **Wave 2** — Google OAuth client → sealed-secret → Dex → ArgoCD/Grafana OIDC config
7. **Validate wave 2** (capability 9)
8. **Wave 3** — verify Cilium `kubeProxyReplacement: false` as a separate scheduled change; install Istio + Kiali (opt-in namespaces only); provision external S3 → sealed AWS creds → Velero + Longhorn backups
9. **Validate wave 3** (capabilities 10–11)

---

## Open Questions

None outstanding. Identity solution, backup provider, ingress layer, DNS strategy, MetalLB subnet (Wi-Fi, accepted), control-plane SPOF (accepted with backup), secrets tool (sealed-secrets), alert sink (Telegram), and Grafana timezone are all decided — captured inline in the relevant capability sections above. Future material changes (e.g. swapping Istio for another mesh, promoting to HA control plane) should be recorded in `DECISIONS.md`.
