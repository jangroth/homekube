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

## Navigation

- [GitHub Issues](https://github.com/jangroth/homekube/issues) — open tasks (single tracker for all three repos)
- [`DECISIONS.md`](DECISIONS.md) — decision log
- [`docs/specs/`](docs/specs/) — specs for significant work items
