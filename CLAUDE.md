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

| Node | Role | Tailscale | Switch (k8s) |
|------|------|-----------|--------------|
| pi0  | Control Plane | pi0 (MagicDNS) | 10.0.0.20 |
| pi1  | Data Plane | pi1 (MagicDNS) | 10.0.0.21 |
| pi2  | Data Plane | pi2 (MagicDNS) | 10.0.0.22 |
| pi3  | Data Plane | pi3 (MagicDNS) | 10.0.0.23 |

Hardware: Raspberry Pi 5 (8GB), Raspberry Pi OS Lite 64-bit (aarch64), 1TB NVMe each.

**Network planes:**
- **Tailscale (management):** darth → pis for SSH, ansible, kubectl — works from any network
- **Physical switch (10.0.0.x):** inter-pi traffic, k8s node network, etcd — Tailscale is invisible to k8s
- **WiFi (wlan0):** internet access only; IP is DHCP, not relied upon

---

## Stack

| Layer | Component |
|-------|-----------|
| Kubernetes | kubeadm (vanilla), v1.36.1 |
| CNI | Cilium 1.19.4 |
| CSI | Longhorn 1.9 |
| GitOps | ArgoCD (App-of-Apps) |
| Monitoring | Prometheus + Grafana + Loki |
| Load Balancer | Cilium LB-IPAM + L2 |
| Provisioning | Ansible + Task |

---

## SSH Access

State depends on phase. After phase 2 (current state), only the `boot` user exists; the `homekube` user is created during phase 3.

- **Bootstrap user:** `boot` / `boot` — password auth. Created at image-build time, used for Tailscale join (phase 1) and ansible bootstrap. Active through phases 1–2; **disabled during phase 3** (`disable_password_auth.yml` + sshd lockdown) once `homekube` is in place.
- **Operational user (post phase 3):** `homekube` — created by ansible, key-auth only, sudoer.
- **From darth:** `ssh homekube@pi0` (or pi1/pi2/pi3) — resolves via Tailscale MagicDNS. Works after phase 3.
- **Darth's key:** `homekube-main/ansible/roles/raspberry-pi/files/pub_keys/id_darth_homekube.pub` is deployed to `authorized_keys` on every pi by `create_user_account.yml`.

All post-bootstrap access goes over Tailscale. No home network or static external IP required.

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
- **Decision log**: record key decisions in `DECISIONS.md`, newest decision first. Decisions capture **why**.
- **Change log**: append every material change to `CHANGELOG.md` (top-level, reverse-chronological, [Keep a Changelog](https://keepachangelog.com) format). Captures **what was done**: additions, version bumps, removals, fixes, operational interventions. Distinct from `DECISIONS.md`.
- **Todo**: open tasks tracked in `TODO.md`
- **Trust**: Claude proposes, human approves for destructive/irreversible operations (this policy evolves over time as trust is established)
- **Source reflects runtime**: when a change is made to a running cluster (static pod manifest, sysctl, Ansible variable), always propagate it back to the canonical source file (`kubeadm-config.yaml`, Ansible role, Helm values) in the same piece of work. The source must be sufficient to rebuild the cluster from scratch.

---

## Key Files

- `TODO.md` — open tasks
- `DECISIONS.md` — decision log (why)
- `CHANGELOG.md` — change log (what was done), top-level, spans all three repos
- `docs/specs/` — specs for significant work items
