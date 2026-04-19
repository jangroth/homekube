# homekube

Workspace for running vanilla Kubernetes on 4x Raspberry Pi 5.

## Repos

| Repo | Purpose |
|------|---------|
| [homekube-main](https://github.com/jangroth/homekube-main) | Ansible provisioning, k8s install, ArgoCD bootstrap |
| [homekube-apps](https://github.com/jangroth/homekube-apps) | ArgoCD applications (App-of-Apps) |

## Cluster

| Node | Role | IP |
|------|------|----|
| pi0 | Control Plane | 192.168.86.220 |
| pi1 | Data Plane | 192.168.86.221 |
| pi2 | Data Plane | 192.168.86.222 |
| pi3 | Data Plane | 192.168.86.223 |

Hardware: Raspberry Pi 5 (8GB), Raspberry Pi OS Lite 64-bit, 1TB NVMe each.

## Stack

Cilium · Longhorn · ArgoCD · Prometheus · Grafana · Loki · MetalLB

## Navigation

- [`TODO.md`](TODO.md) — open tasks
- [`DECISIONS.md`](DECISIONS.md) — decision log
- [`docs/specs/`](docs/specs/) — specs for significant work items
