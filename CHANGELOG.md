# Changelog

All notable changes to the homekube project (`homekube/`, `homekube-main/`, `homekube-apps/`).

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Entries are reverse-chronological; each dated section groups changes by type:

- **Added** — new components, files, or capabilities
- **Changed** — modifications to existing config, versions, or behaviour
- **Removed** — deletions and decommissioning
- **Fixed** — bug fixes
- **Operational** — manual interventions, recoveries, one-off ops actions
- **Decisions** — links to `DECISIONS.md` entries created on this day

Cross-repo entries reference commits as `repo@sha` (e.g. `homekube-main@e77a322`). Where a change has an associated decision or spec, link it inline.

---

## 2026-06-29

### Changed
- Spec 005 cap-8 (Dashboards & Alerting) reviewed and rewritten: Grafana deployed as the `kube-prometheus-stack` subchart (re-enabled in `kube-prometheus.yaml`), exposed on Cilium LB-IPAM VIP `192.168.86.243`, stateless (no PVC); Loki added via `additionalDataSources`; Longhorn dashboard via sidecar ConfigMap; Telegram `bot_token_file` mount mechanism spelled out
- Removed stale MetalLB / NodePort `:30003` references from cap-8; Grafana TLS deferred from cap-8 to cap-9 (cap-9 §gains the IP-SAN cert constraint + acceptance box)

### Decisions
- [DECISION-036](DECISIONS.md) — Grafana as kube-prometheus-stack subchart; LB VIP `.243`; TLS deferred to cap-9

---

## 2026-06-22

### Added
- Cilium LB-IPAM + L2 announcements: `CiliumLoadBalancerIPPool` (`homekube-pool`, `192.168.86.241–251`) and `CiliumL2AnnouncementPolicy` (`homekube-l2`, wlan0, workers only) deployed via ArgoCD (`cilium-lb` app, wave -1)
- Network architecture diagram in `homekube-main/README.md` showing all three network planes (Tailscale, Wi-Fi, k8s switch) and both LB traffic paths

### Changed
- `cilium-helm-values.yaml`: `devices` → `eth0,wlan0,tailscale0`; added `l2announcements.enabled: true`; `k8sClientRateLimit qps:50/burst:100`
- `CLAUDE.md` stack table: MetalLB → Cilium LB-IPAM + L2
- `README.md`: stack line drops MetalLB, notes Cilium (CNI + LB)
- `homekube-main/README.md`: cluster architecture Mermaid updated (MetalLB → Cilium LB, pi1/2/pi3 corrected); network architecture diagram added
- `homekube-apps/CLAUDE.md` wave table: MetalLB → Cilium LB (pool + L2 policy)
- `homekube-apps/README.md` deployed components: added Cilium LB-IPAM, cert-manager, kubelet-csr-approver rows
- `configure_tailscale_subnet.yml` task name: "MetalLB pool" → "LoadBalancer pool (Cilium LB-IPAM)"
- `check-versions.md`: removed metallb helm repo line

### Removed
- MetalLB: `metallb.yaml` Application, `metallb/` CRs, `metallb-system` namespace; 9 MetalLB CRDs manually deleted post-ArgoCD-prune (Helm safety policy prevents auto-deletion)

### Decisions
- [DECISION-032](DECISIONS.md) — add `tailscale0` to Cilium devices so `cil_from_netdev` intercepts Tailscale → VIP traffic on pi0; validated 36/36 over 3 min. Wi-Fi path intermittent (wlan0 dual-use + BPF reload windows); tracked in Backlog.

---

## 2026-06-20

### Added
- `docs/specs/006-cilium-native-loadbalancer.md` — executable spec to replace MetalLB with Cilium-native LB-IPAM + L2 announcements; written self-contained for execution in a later session. No cluster changes yet — planning only.

### Changed
- `docs/specs/005-production-cluster-setup.md` — capability 4 marked **superseded by spec 006**; its acceptance boxes flagged as not actually met (LB IPs unreachable per DECISION-030).
- `TODO.md` — capability 4 metallb item replaced with the spec 006 cutover step list (Steps 0–5).

### Decisions
- [DECISION-031](DECISIONS.md) — replace MetalLB with Cilium-native LB-IPAM + L2 announcements; resolves the DECISION-030 dead end while keeping eBPF kube-proxy replacement and home-Wi-Fi reachability. Pool and Tailscale `192.168.86.240/28` route unchanged.

---

## 2026-06-18

### Added
- kubelet-csr-approver `1.2.14` deployed to `kube-system` (spec 005 capability 3); `bypassDnsResolution: true` required because node hostnames are not resolvable from within the cluster
- Ansible: `configure_kubelet_node_ip.yml` task sets `--node-ip={{ node_switch_ip }}` on all nodes via `/etc/default/kubelet`, preventing Wi-Fi and Tailscale IPs from appearing in kubelet serving CSR SANs

### Operational
- cert-manager validation: applied a test `Certificate` against `ClusterIssuer/homekube-ca`, confirmed `Ready=True` and secret populated, cleaned up — spec 005 capability 2 acceptance complete
- kubelet-csr-approver: accidentally deleted `kubelet-client-current.pem` target on pi2 during serving cert teardown; recovered via `kubeadm token create` bootstrap re-join

---

## 2026-05-23 — Baseline

End of Phase 5 bootstrap. Cluster is a working, minimalistic Kubernetes installation. Future changes are tracked from this point onward.

### Cluster state at baseline
- 4-node `kubeadm` cluster, Kubernetes **1.36.1** (control plane: `pi0`; workers: `pi1`, `pi2`, `pi3`)
- CNI: **Cilium 1.19.4**
- GitOps: **ArgoCD 9.5.14**, root-app synced (App-of-Apps)
- **metrics-server** installed; `kubectl top nodes` returns CPU/memory for all nodes
- `argocd-config` synced (NodePort `:30000`)
- ArgoCD waves wired: `wave-00-init` active; `wave-01-apps`, `wave-02-custom` placeholders

### Not yet present (Phase 5 targets — see `docs/specs/005-production-cluster-setup.md`)
- Persistent storage (Longhorn)
- Service exposure (MetalLB)
- Observability (Prometheus / Loki / Grafana)
- Identity / SSO (Dex)
- Service mesh (Istio)
- Backups & DR (Velero + etcd snapshots + Longhorn → S3)

### Known operational gaps
- kubelet `kubernetes.io/kubelet-serving` CSRs require manual bulk approval
- No off-cluster backups
- All cluster UIs exposed via NodePort; no DNS, no ingress

### Decisions captured during phases 1–5
See `DECISIONS.md` (entries 001–016).
