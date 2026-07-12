# homekube

Workspace for running vanilla Kubernetes on 4x Raspberry Pi 5.

## Getting Started

Clone this repo first, then the two sub-repos into it:

```bash
# Using gh (recommended)
gh repo clone jangroth/homekube
cd homekube
gh repo clone jangroth/homekube-main
gh repo clone jangroth/homekube-apps

# Using git
git clone https://github.com/jangroth/homekube.git
cd homekube
git clone https://github.com/jangroth/homekube-main.git
git clone https://github.com/jangroth/homekube-apps.git
```

## Repos

| Repo | Purpose |
|------|---------|
| [homekube](https://github.com/jangroth/homekube) | This repo — workspace root, decisions, specs, todos |
| [homekube-main](https://github.com/jangroth/homekube-main) | Ansible provisioning, k8s install, ArgoCD bootstrap |
| [homekube-apps](https://github.com/jangroth/homekube-apps) | ArgoCD applications (App-of-Apps) |

## Cluster

| Node | Role            | Tailscale | Boot  |
|------|-----------------|-----------|-------|
| pi0  | Control Plane   | pi0       | NVMe  |
| pi1  | Data Plane      | pi1       | NVMe  |
| pi2  | Data Plane      | pi2       | NVMe  |
| pi3  | Data Plane      | pi3       | NVMe  |

**Hardware:** Raspberry Pi 5 (8GB), Raspberry Pi OS Lite 64-bit, 1TB NVMe each.

**Access:** All management via Tailscale (100.x.x.x MagicDNS). Physical switch (10.0.0.x) for inter-pi k8s traffic only.

## Stack

Cilium (CNI + LB) · Longhorn · ArgoCD · Prometheus · Grafana · Loki

## Resource Budget

Rough RAM allocation, sized for 4×8 GiB = 32 GiB total. Numbers are `requests`; `limits` set 1.5–2× for burst headroom. System reserved (kubelet/containerd/Cilium/CoreDNS/sealed-secrets/cert-manager) ≈ 1 GiB/node = 4 GiB. Anything above is workload budget.

### Deployed

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
| 7 | Loki (monolithic) | 1 GiB | filesystem backend on Longhorn PVC |
| 7 | Alloy ×4 | 512 MiB | |
| 8 | Grafana | 256 MiB | |
| 9 | Dex | 128 MiB | |
| — | **Subtotal (deployed)** | **~6.5 GiB** | |

### Planned

| Capability | Component | RAM request | Notes |
|---|---|---|---|
| 10 | Istio (istiod + gateway, no sidecars) | 1 GiB | sidecars budgeted per opt-in namespace |
| 11 | Velero | 256 MiB | |
| — | **Subtotal (planned)** | **~1.25 GiB** | |

### Headroom

| | RAM |
|---|---|
| System reserved (4 nodes) | ~4 GiB |
| Deployed workload subtotal | ~6.5 GiB |
| **Current headroom** | **~21.5 GiB** |
| Planned workload subtotal | ~1.25 GiB |
| **Headroom after planned deploys** | **~20.25 GiB** |

Sidecar overhead is *not* in either subtotal — each opted-in namespace adds ~80–120 MiB per pod. Audit before enabling injection in a busy namespace.

Update this table in the same piece of work whenever a workload's resource requests/limits change (new component, resize, removal) — see "source reflects runtime" in `CLAUDE.md`.

## Navigation

- [GitHub Issues](https://github.com/jangroth/homekube/issues) — open tasks (single tracker for all three repos)
- [`DECISIONS.md`](DECISIONS.md) — decision log
- [`docs/specs/`](docs/specs/) — specs for significant work items
