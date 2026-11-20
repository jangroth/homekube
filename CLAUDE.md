# Homekube — AI Workspace

Vanilla Kubernetes on 4x Raspberry Pi 5 (8GB), run as a study project for both Kubernetes and AI-driven development.

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
| Kubernetes | kubeadm (vanilla) |
| CNI | Cilium — **held**, do not bump (ADR-0004) |
| CSI | Longhorn |
| GitOps | ArgoCD (App-of-Apps) |
| Monitoring | Prometheus + Grafana + Loki |
| Load Balancer | Cilium LB-IPAM + L2 |
| Provisioning | Ansible + Task |
| Cloud IaC | Terraform (AWS-account resources — ADR-0010) |

Versions live in `homekube-main/ansible/group_vars/all.yml` (Renovate-owned, ADR-0008) and `homekube-apps/applications/**/*.yaml` → `targetRevision`. `task verify-drift` in `homekube-main` checks runtime against them (ADR-0009).

---

## SSH Access

`ssh homekube@piN` from darth over Tailscale MagicDNS: key auth only, sudoer. Darth's key is `homekube-main/ansible/roles/raspberry-pi/files/pub_keys/id_darth_homekube.pub`.

A rebuilt pi goes through the bootstrap again (see `homekube-main/CLAUDE.md`), starting with a **one-time physical NVMe step** a human has to do; ansible handles the rest.

---

## Working Approach

- **Spec-driven**: write a spec in `docs/specs/NNN-title.md` before any significant implementation. Specs define the problem, acceptance criteria, and approach.
- **Decisions**: ADRs in `docs/adr/`, written through `domain-modeling` and only for decisions that are hard to reverse, surprising without context, and the result of a real trade-off.
- **Archive**: `docs/archive/` (decision log, changelog) is read-only history; never append to it. Search them (`ctx_search`) when an old decision number is cited. What changed is recorded by merged PRs.
- **Todo**: open tasks tracked as GitHub Issues on `jangroth/homekube` (single tracker for all three repos). Triage labels come from the user-level `CLAUDE.md`; on top, issues are labelled `area:*` (component), `criticality:blocker`/`degraded`/`polish` (workload-readiness impact) and `repo:*` (which repo the fix lands in — `homekube`/`homekube-main`/`homekube-apps`). `ready-for-agent` issues in `homekube-apps` and `homekube-main` are picked up nightly by scheduled routines that open a PR for human review; before taking one, check for an in-flight `auto/issue-<n>-*` PR.
- **Trust**: Claude proposes, human approves for destructive/irreversible operations.
- **Source reflects runtime**: when a change is made to a running cluster (static pod manifest, sysctl, Ansible variable), always propagate it back to the canonical source file (`kubeadm-config.yaml`, Ansible role, Helm values) in the same piece of work. The source must be sufficient to rebuild the cluster from scratch.

---

## Agent skills

Use a Matt Pocock skill whenever one covers the task (spec, tickets, grilling, glossary/ADRs, triage, PR body, review); never hand-write the equivalent. Many run only as slash commands (`/to-spec`, `/to-tickets`, `/grill-with-docs`, `/triage`): ask the user to run the command.

### Issue tracker

GitHub Issues on `jangroth/homekube`, the single tracker for all three repos. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the root, ADRs in `docs/adr/`. See `docs/agents/domain.md`.
