# homekube

Workspace for running vanilla Kubernetes on 4x Raspberry Pi 5.

## Repos

| Repo | Purpose |
|------|---------|
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

Cilium · Longhorn · ArgoCD · Prometheus · Grafana · Loki · MetalLB

## Navigation

- [`TODO.md`](TODO.md) — open tasks
- [`DECISIONS.md`](DECISIONS.md) — decision log
- [`docs/specs/`](docs/specs/) — specs for significant work items
