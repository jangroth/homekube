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

## 2026-06-18

### Operational
- cert-manager validation: applied a test `Certificate` against `ClusterIssuer/homekube-ca`, confirmed `Ready=True` and secret populated, cleaned up — spec 005 capability 2 acceptance complete

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
