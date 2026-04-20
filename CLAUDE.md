# Homekube — AI Workspace

Running vanilla Kubernetes on 4x Raspberry Pi 5 (8GB).

**Dual purpose**: study Kubernetes + study AI-driven development.

---

## Repos

| Repo | Purpose |
|------|---------|
| `homekube-main/` | Ansible provisioning, k8s install, ArgoCD bootstrap |
| `homekube-apps/` | ArgoCD applications (App-of-Apps pattern) |

Each has its own `CLAUDE.md` with repo-specific context.

---

## Cluster

| Node | Role | External IP | Internal IP |
|------|------|-------------|-------------|
| pi0  | Control Plane | 192.168.86.220 | 10.0.0.20 |
| pi1  | Data Plane | 192.168.86.221 | 10.0.0.21 |
| pi2  | Data Plane | 192.168.86.222 | 10.0.0.22 |
| pi3  | Data Plane | 192.168.86.223 | 10.0.0.23 |

Hardware: Raspberry Pi 5 (8GB), Raspberry Pi OS Lite 64-bit (aarch64), 1TB NVMe each.

---

## Stack

| Layer | Component |
|-------|-----------|
| Kubernetes | kubeadm (vanilla), v1.35 |
| CNI | Cilium 1.18 |
| CSI | Longhorn 1.9 |
| GitOps | ArgoCD (App-of-Apps) |
| Monitoring | Prometheus + Grafana + Loki |
| Load Balancer | MetalLB |
| Provisioning | Ansible + Task |

---

## SSH Access

- **From this machine (darth):** `ssh homekube@pi0` (or pi1/pi2/pi3)
- **User on pis:** `homekube` — created by ansible, key-auth only
- **Darth's key:** `homekube-main/ansible/roles/raspberry-pi/files/pub_keys/id_darth_homekube.pub` is in `authorized_keys` on all pis after provisioning
- **Bootstrap user (fresh SD card only):** `boot` / `boot` — used by ansible to create the `homekube` user, then disabled

The hosts `pi0`–`pi3` should resolve after the control-node ansible role runs (updates `/etc/hosts` and `~/.ssh/config` on darth).

---

## NVMe Boot — Manual Checkpoint

Each pi has a 1TB NVMe drive. Booting from NVMe requires a **one-time physical step per pi** (vendor instruction, involves physically configuring the NVMe hardware). This is a human checkpoint — it cannot be automated.

After the physical step, ansible handles the rest:
1. Enable PCIe (`enable_pciex.yml`)
2. Configure NVMe boot (`configure_nvme.yml`)
3. Copy SD card to NVMe (`copy_mmc_to_nvme.yml`)

---

## Working Approach

- **Spec-driven**: write a spec in `docs/specs/NNN-title.md` before any significant implementation. Specs define the problem, acceptance criteria, and approach.
- **Decision log**: record key decisions in `DECISIONS.md`, newest decision first
- **Todo**: open tasks tracked in `TODO.md`
- **Trust**: Claude proposes, human approves for destructive/irreversible operations (this policy evolves over time as trust is established)

---

## Key Files

- `TODO.md` — open tasks
- `DECISIONS.md` — decision log
- `docs/specs/` — specs for significant work items
