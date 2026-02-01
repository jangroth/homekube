# Product Requirements Document: homekube

**Version:** 1.0
**Date:** 1 February 2026
**Owner:** Jan Groth
**Status:** Active Development

---

## Executive Summary

**homekube** is a production-grade Kubernetes automation framework for running upstream Kubernetes on Raspberry Pi hardware. The project delivers a fully automated, GitOps-driven cluster lifecycle using Ansible and ArgoCD, optimised for ARM64 architecture and home lab environments.

### What Problem Does This Solve?

- **Manual Kubernetes Setup Pain:** Eliminates the 4-6 hour manual setup process for Pi clusters
- **Configuration Drift:** Prevents cluster state inconsistencies through declarative infrastructure
- **Knowledge Loss:** Captures institutional knowledge in code rather than scattered docs
- **Reproducibility:** Enables cluster rebuild in under 1 hour with zero manual intervention

---

## Goals & Non-Goals

### Goals

1. **Automated Cluster Lifecycle**
   - One-command cluster initialisation from bare metal
   - Idempotent playbooks that can run repeatedly without side effects
   - Version-controlled infrastructure state

2. **Production-Ready Observability**
   - Prometheus + Grafana for metrics
   - Loki for centralised logging
   - Resource monitoring across all nodes

3. **GitOps-First Application Deployment**
   - ArgoCD as the single source of truth for workloads
   - App-of-Apps pattern for hierarchical deployment
   - Automatic sync of applications from Git

4. **High Availability Storage**
   - Longhorn distributed storage across worker nodes
   - NVMe-backed persistent volumes
   - Snapshot and backup capabilities

### Non-Goals

- **Multi-Cluster Federation:** Single cluster focus (not managing fleet of clusters)
- **Cloud Portability:** Optimised for Pi hardware, not generic cloud deployment
- **Enterprise Features:** No RBAC/LDAP integration, single-user focused
- **Cost Optimisation:** Not optimising for cloud spend (fixed hardware cost)

---

## Target User

**Primary Persona:** Self (Jan Groth)

- Experienced with Kubernetes, wants hands-on learning cluster
- Requires reproducible infrastructure for experimentation
- Values automation over manual processes
- Needs cluster to survive hardware failures and config changes

**Secondary Persona:** Advanced Home Lab Enthusiasts

- Running similar Pi-based clusters
- Looking for production-ready patterns (not toy examples)
- Comfortable with Ansible, Kubernetes, and Git

---

## Technical Architecture

### Stack Selection Rationale

| Component | Choice | Reasoning |
|-----------|--------|-----------|
| **Kubernetes** | Upstream (kubeadm) | Learn "real" K8s, not K3s/MicroK8s simplifications |
| **CNI** | Cilium (eBPF) | Performance + observability + security features |
| **CSI** | Longhorn | Kubernetes-native, designed for distributed storage |
| **GitOps** | ArgoCD | Mature, UI-driven, better debugging than Flux |
| **IaC** | Ansible | Imperative control for OS/cluster setup, declarative K8s later |

### Hardware Constraints

- **Fixed Topology:** 4x Raspberry Pi 5 (8GB RAM, NVMe storage)
- **Network:** Single-subnet LAN (192.168.86.0/24)
- **Power:** Cluster must survive graceful shutdown (no UPS)

---

## Feature Requirements

### Phase 0: Hardware Prerequisites 🔧 (Manual)

**These steps CANNOT be fully automated and require physical access to hardware.**

| Task | Priority | Effort | Automation Feasibility |
|------|----------|--------|------------------------|
| NVMe Drive Installation | P0 | 30 min | ❌ Impossible (physical hardware) |
| NVMe Drive Partitioning | P0 | 15 min | ⚠️ Risky (data loss if misconfigured) |
| NVMe Drive Formatting | P0 | 10 min | ⚠️ Risky (destructive operation) |
| Boot Configuration (boot from NVMe) | P0 | 20 min | ⚠️ Risky (can brick Pi if wrong) |
| Initial OS Image Flash | P0 | 15 min | 🔧 Semi-automated (manual SD card insert) |

**Rationale for Manual Process:**
- **Data Loss Risk:** Automating drive formatting could wipe wrong disk
- **Hardware Variance:** NVMe adapter/HAT setup differs by vendor
- **Boot Loader Fragility:** Incorrect bootloader config can render Pi unbootable
- **Physical Access Required:** Plugging in NVMe drives requires human hands

**Documentation:** See `doc/02_01_node-configuration.md` for step-by-step manual procedures.

### Phase 1: Cluster Foundation ✅ (Completed)

| Feature | Priority | Status | Implementation |
|---------|----------|--------|----------------|
| OS Preparation (Pi nodes) | P0 | ✅ Done | `02-prepare-pis.yml` |
| Kubernetes Installation | P0 | ✅ Done | `04-setup-k8s-control-plane.yml` |
| Cilium CNI Deployment | P0 | ✅ Done | `05-setup-cni.yml` |
| ArgoCD Rollout | P0 | ✅ Done | `06-setup-gitops.yml` |
| Longhorn Storage | P0 | ✅ Done | ArgoCD app deployment |
| MetalLB LoadBalancer | P1 | ✅ Done | ArgoCD app deployment |

### Phase 2: Observability ✅ (Completed)

| Feature | Priority | Status | Implementation |
|---------|----------|--------|----------------|
| Prometheus Stack | P0 | ✅ Done | Kube-Prometheus-Stack via ArgoCD |
| Grafana Dashboards | P1 | ✅ Done | Pre-configured via Helm values |
| Loki Logging | P1 | ✅ Done | ArgoCD app deployment |
| Alloy (Grafana Agent) | P2 | ✅ Done | Log collection across nodes |

### Phase 3: Operational Excellence 🚧 (In Progress)

| Feature | Priority | Status | Acceptance Criteria |
|---------|----------|--------|---------------------|
| Cluster Shutdown Script | P1 | ✅ Done | All nodes gracefully stop via Ansible |
| Automated Backups | P1 | ⏳ Planned | Longhorn snapshots scheduled + verified |
| Config Drift Detection | P2 | ⏳ Planned | Alert on Ansible vs actual state mismatch |
| Disaster Recovery Runbook | P2 | 🚧 Partial | Full cluster rebuild tested < 90 minutes |

### Phase 4: Advanced Workloads ⏳ (Future)

| Feature | Priority | Status | Requirements |
|---------|----------|--------|--------------|
| Ingress Controller | P1 | ⏳ Planned | Traefik or nginx-ingress via ArgoCD |
| SSL Certificates | P1 | ⏳ Planned | cert-manager + Let's Encrypt |
| External DNS | P2 | ⏳ Planned | Automatic DNS updates for services |
| Gitea Self-Hosted Git | P3 | ⏳ Backlog | Replace GitHub dependency for GitOps |

---

## Success Criteria

### Key Performance Indicators

1. **Cluster Rebuild Time:** < 60 minutes from **NVMe-ready Pi** to working ArgoCD
   - *Current:* ~45 minutes (manual prep) + 15 minutes (Ansible) = 60 minutes ✅
   - *Excludes:* NVMe hardware setup (~90 minutes one-time per node)
   - *Assumption:* Drives already partitioned, OS image flashed

2. **Configuration Drift Events:** Zero manual SSH changes to production nodes
   - *Measured by:* Audit log of changes via Git commits only

3. **Uptime:** 99% availability for control plane services
   - *Excludes:* Planned maintenance windows and power outages

4. **Storage Reliability:** Zero data loss events from Longhorn
   - *Measured by:* Backup restore tests monthly

### Failure Modes Handled

- ✅ **Single Worker Node Failure:** Workloads reschedule automatically
- ✅ **Power Loss:** Cluster survives graceful shutdown (requires manual restart)
- ✅ **Network Partition:** Cilium handles intermittent connectivity
- ⏳ **Control Plane Failure:** Manual rebuild required (no HA control plane)
- ⏳ **Storage Corruption:** Longhorn snapshots enable rollback

---

## Dependencies & Risks

### External Dependencies

| Dependency | Risk Level | Mitigation |
|------------|-----------|------------|
| GitHub (ArgoCD repo) | Medium | Consider self-hosted Gitea |
| Container Registry (quay.io, gcr.io) | Medium | Local Harbor registry planned |
| Ansible Galaxy Collections | Low | Vendored in `ansible/` directory |
| Raspberry Pi OS Updates | Low | Controlled update schedule |

### Technical Risks

1. **NVMe Setup Complexity:** Drive partitioning/formatting is manual and error-prone
   - *Impact:* Initial cluster setup requires 90+ minutes of careful manual work
   - *Mitigation:* Detailed runbook (`doc/02_01_node-configuration.md`), validation scripts
   - *Acceptance:* Cannot be fully automated due to data loss risk and hardware variance

2. **ARM64 Image Availability:** Some containers lack ARM builds
   - *Mitigation:* Build custom images, document alternatives

3. **SD Card Failures (Historical):** Early cluster used SD cards (failed frequently)
   - *Mitigation:* Migrated to NVMe storage (2025) ✅

4. **Kernel Module Compatibility:** Longhorn/Cilium require specific modules
   - *Mitigation:* Ansible validates modules before install

---

## Out of Scope

The following are explicitly **not** in scope for this project:

- **Automated NVMe Setup:** Physical drive installation, partitioning, and boot config remain manual (too risky to automate)
- **Multi-Tenancy:** Single-user cluster (no namespace isolation)
- **Compliance:** No PCI-DSS/SOC2 requirements
- **High Availability Control Plane:** Cost/complexity not justified
- **GPU Workloads:** Pi 5 GPU not supported by CUDA/ROCm
- **Windows Workloads:** Linux containers only

---

## Documentation Requirements

### Must-Haves

1. **Setup Runbook** (`doc/02_*.md`) — Step-by-step cluster build ✅
2. **AI Context Map** (`AI-CONTEXT.md`) — Infrastructure source of truth ✅
3. **Ansible Inventory** (`ansible/inventory/hosts`) — Node definitions ✅
4. **ArgoCD Apps** (`homekube-apps/`) — Application manifests ✅

### Nice-to-Haves

- Architecture diagrams (Mermaid in README) ✅
- Troubleshooting guide (common failure modes) ⏳
- Video walkthrough of cluster build ⏳

---

## Versioning & Changelog

This PRD follows the cluster's evolution:

| Version | Date | Major Changes |
|---------|------|---------------|
| 0.1 | 2024-Q3 | Initial cluster with K3s (deprecated) |
| 0.5 | 2025-Q1 | Migrated to upstream Kubernetes + kubeadm |
| 0.8 | 2025-Q4 | Added Cilium, Longhorn, full observability stack |
| 1.0 | 2026-Q1 | Ansible automation complete, GitOps-only deploys |

**Next Review Date:** 1 May 2026 (quarterly review cycle)

---

## Appendix: Technology Decisions

### Why Ansible (Not Terraform)?

- **OS-level tasks:** Package management, kernel modules, systemd units
- **Imperative control:** Sometimes "just do this command" is clearer than HCL
- **No state files:** Avoids Terraform state corruption issues

### Why Upstream Kubernetes (Not K3s)?

- **Learning value:** Forces understanding of kubeadm, CNI, CSI concepts
- **Production parity:** Closer to EKS/GKE patterns than K3s
- **Community support:** More resources for troubleshooting

### Why Cilium (Not Calico)?

- **eBPF performance:** Lower latency, better throughput vs iptables
- **Built-in observability:** Hubble for network debugging
- **Future-proof:** eBPF is the direction of Linux networking

### Why Longhorn (Not NFS)?

- **Kubernetes-native:** No external NFS server dependency
- **Replication:** Survives single-node failures
- **Snapshots:** Built-in backup capabilities

---

## Contact & Contribution

**Primary Maintainer:** Jan Groth (@jangroth)
**Repository:** [github.com/jangroth/homekube](https://github.com/jangroth/homekube)
**Licence:** MIT

**Contribution Policy:**
This is a personal project, but PRs welcome for:
- Bug fixes in Ansible playbooks
- Documentation improvements
- ARM64-compatible application examples

**Not Accepting:**
- Feature requests for cloud providers
- PRs that break Raspberry Pi compatibility
- Changes requiring non-free software
