# AI Context Map: homekube Infrastructure Source of Truth

**Last Updated:** 31 January 2026  
**Cluster Version:** Kubernetes 1.35 on Raspberry Pi 5 (aarch64)  
**Purpose:** This file defines the **non-negotiable architectural decisions** for homekube. When AI tools reference this repo, these facts override any external assumptions.

---

## 1. Hardware Topology

| Node | Hardware | Storage | Static IP | Internal IP | Role |
|------|----------|---------|-----------|-------------|------|
| pi0 | Raspberry Pi 5 8GB | NVMe (PCIe) | 192.168.86.220 | 10.0.0.20 | Control Plane |
| pi1 | Raspberry Pi 5 8GB | NVMe (PCIe) | 192.168.86.221 | 10.0.0.21 | Worker |
| pi2 | Raspberry Pi 5 8GB | NVMe (PCIe) | 192.168.86.222 | 10.0.0.22 | Worker |
| pi3 | Raspberry Pi 5 8GB | NVMe (PCIe) | 192.168.86.223 | 10.0.0.23 | Worker |

**Source Files:**

- `ansible/inventory/hosts` — Ansible inventory
- `ansible/group_vars/raspberry_pis.yml` — Node-specific variables
- `doc/02_01_node-configuration.md` — Hardware setup procedures

**Critical Facts:**

- NVMe drives are primary storage (not SD cards in production)
- Static IPs are assigned at router level (DHCP reservation)
- SSH access via `homekube` user (not `pi` or `root`)

---

## 2. Kubernetes Network Architecture

### Network Allocations

```yaml
Pod Network (CIDR):        10.244.0.0/16
Service Network (CIDR):    10.96.0.0/12
Cluster DNS (IP):          10.96.0.10
NodePort Range:            30000-32767
```

**Source Files:**

- `ansible/roles/kubeadm/files/kubeadm-config.yaml` — Cluster initialization config
- `ansible/roles/cilium/` — CNI configuration

**CNI Implementation:**

- **Cilium 1.18.2** (eBPF-based, not iptables)
- Native routing mode (no overlay)
- Cluster Mesh: disabled
- Hubble: enabled (observability)

**Why Cilium:** eBPF performance, native ARM64 support, advanced network policies.

---

## 3. Storage Architecture

### Primary CSI: Longhorn 1.9.1

**Deployment:**

- Installed via ArgoCD (see `homekube-apps/applications/wave-00-init/longhorn.yaml`)
- 3-replica configuration (default)
- Backend: NVMe drives on each node at `/var/lib/longhorn`

**Storage Classes:**

```yaml
longhorn:              # Default, 3 replicas
longhorn-single:       # 1 replica (non-production)
longhorn-test:         # 2 replicas (staging)
```

**Source Files:**

- `homekube-apps/applications/wave-00-init/longhorn.yaml` — ArgoCD app definition
- `ansible/roles/k8s-node/tasks/storage.yml` — NVMe prep for Longhorn

**Do Not Use:**

- `local-path` (only for testing/debugging)
- `hostPath` (insecure, non-portable)
- NFS (not configured in this cluster)

---

## 4. Container Runtime

**CRI:** containerd 2.1.4  
**Runtime:** runc 1.1.5  
**CNI Plugins:** containernetworking-plugins 1.1.1

**Source Files:**

- `ansible/roles/k8s-node/tasks/containerd.yml` — Installation and configuration
- `/etc/containerd/config.toml` (on nodes) — Runtime config

**Key Config:**

- `SystemdCgroup = true` (required for cgroup v2)
- Sandbox image: `registry.k8s.io/pause:3.10`
- No Docker shim (native containerd)

**CLI Tools:**

- `crictl` — container runtime CLI (not `docker`)
- `ctr` — low-level containerd CLI

---

## 5. GitOps Pipeline: ArgoCD

### ArgoCD Installation

- **Namespace:** `argocd`
- **Chart Version:** 9.1.2 (Helm)
- **Access:** NodePort 30000 (pi0:30000)

**Source Files:**

- `ansible/roles/argocd/` — Helm installation
- `ansible/group_vars/all.yml` — Version pinning

### Application Repository: `jangroth/homekube-apps`

```
applications/
├── kustomization.yaml              # Root app (wave -2)
├── wave-00-init/                   # Wave -1 (infrastructure)
│   ├── metallb.yaml
│   ├── metrics-server.yaml
│   └── longhorn.yaml (if added)
├── wave-01-apps/                   # Wave 1 (applications)
│   ├── kubernetes-dashboard.yaml
│   └── test-lb.yaml
└── wave-02-custom/                 # Wave 2 (user apps)
```

**Sync Waves:** Control deployment order (negative waves first)  
**Auto-Sync:** Enabled for all apps  
**Pruning:** Enabled (ArgoCD removes deleted resources)

**Manual Deployments:** `homekube-apps/manual/` (not synced by ArgoCD, used for debugging)

---

## 6. Component Version Matrix

**Source of Truth:** `ansible/group_vars/all.yml`

| Component | Variable Name | Version | Update Playbook |
|-----------|--------------|---------|-----------------|
| Kubernetes | `kubernetes_version` | 1.35 | `04-setup-k8s-control-plane.yml` |
| containerd | `containerd_version` | 2.1.4 | `03-setup-k8s-nodes.yml` |
| Cilium | `cilium_version` | 1.18.2 | `05-setup-cni.yml` |
| Longhorn | `longhorn_version` | 1.9.1 | ArgoCD app sync |
| ArgoCD | `argocd_helm_chart_version` | 9.1.2 | `06-setup-gitops.yml` |

**Compatibility Notes:**

- Kubernetes 1.35 requires Cilium 1.18+
- Longhorn 1.9.1 supports Kubernetes 1.30-1.35
- containerd 2.x required for Kubernetes 1.35+

---

## 7. Ansible Execution Model

### Playbook Dependency Chain

```mermaid
graph LR
    A[01-update-control-node] --> B[02-prepare-pis]
    B --> C[03-setup-k8s-nodes]
    C --> D[04-setup-k8s-control-plane]
    D --> E[05-setup-cni]
    E --> F[06-setup-gitops]
```

### Idempotency Status

| Playbook | Idempotent | Manual Steps | Re-run Safe |
|----------|------------|--------------|-------------|
| 01-update-control-node | ✅ Yes | Requires `--ask-become-pass` | ✅ Yes |
| 02-prepare-pis | ❌ No | Bootloader update, NVMe copy | ⚠️ Only with tags |
| 03-setup-k8s-nodes | ✅ Yes | None | ✅ Yes |
| 04-setup-k8s-control-plane | ⚠️ Partial | First run only | ⚠️ Use `kubeadm reset` first |
| 05-setup-cni | ✅ Yes | None | ✅ Yes (upgrades Cilium) |
| 06-setup-gitops | ✅ Yes | None | ✅ Yes (upgrades ArgoCD) |

### Common Tags

```yaml
--tags update-only      # Update packages/tools without config changes
--tags init             # Initial Pi setup (playbook 02)
--tags nvme             # NVMe configuration (playbook 02)
```

---

## 8. Security and Access

### SSH Configuration

- **User:** `homekube` (sudo privileges)
- **Auth:** SSH keys only (password auth disabled)
- **Control Node:** `~/.ssh/config` managed by playbook 01

### Kubernetes RBAC

- **Admin:** `cluster-admin` role (via kubeconfig)
- **ArgoCD:** Dedicated service account (see ArgoCD role)
- **TLS Bootstrap:** Enabled for kubelet certificates

### Secrets Management

- **Not in Git:** Actual secrets never committed
- **Patterns:** See `secrets.md` for secret naming conventions
- **Vault:** Not currently implemented (future consideration)

---

## 9. Observability Stack

### Metrics

- **metrics-server:** Core cluster metrics (CPU, memory)
- **Prometheus:** (Future) Full metrics scraping
- **Grafana:** (Future) Dashboards

### Logging

- **Loki:** (Future) Log aggregation
- **Alloy:** (Future) Log forwarding

### Networking

- **Hubble:** Cilium network observability (UI and CLI)

**Source Files:**

- `homekube-apps/applications/wave-00-init/metrics-server.yaml`
- `homekube-apps/manual/loki/` — Manual Loki experiments

---

## 10. Operational Runbooks

### Cluster Upgrade Process

1. Update `kubernetes_version` in `ansible/group_vars/all.yml`
2. Run `ansible-playbook 03-setup-k8s-nodes.yml` (updates kubeadm/kubelet)
3. SSH to pi0: `sudo kubeadm upgrade plan`
4. SSH to pi0: `sudo kubeadm upgrade apply v1.X.Y`
5. Drain and upgrade worker nodes one-by-one
6. Verify: `kubectl get nodes` (all nodes on new version)

### Adding a New Worker Node

1. Add node to `ansible/inventory/hosts`
2. Run playbooks 02, 03 for new node
3. On new node: `kubeadm join` (token from pi0)
4. Verify: `kubectl get nodes`
5. Label if needed: `kubectl label node piX node-role.kubernetes.io/worker=worker`

### Disaster Recovery

- **etcd Backups:** Manual via `etcdctl snapshot save` (not automated yet)
- **Longhorn Backups:** Not configured (future: S3 backup target)
- **GitOps Recovery:** Re-run playbook 06, ArgoCD restores all apps

---

## 11. Known Limitations and Gotchas

### Raspberry Pi Specific

- **NVMe Heat:** Drives can throttle under heavy I/O (monitor temps)
- **Power:** All Pis on single power supply (risk of simultaneous failure)
- **USB Boot:** NVMe boot requires bootloader update (see playbook 02)

### Kubernetes

- **Pod Eviction:** Low memory triggers eviction (8GB limit per node)
- **ImagePullBackOff:** ARM64 images only (no x86_64 emulation)
- **NodePort Range:** Hard-limited to 30000-32767

### Networking

- **MetalLB:** L2 mode only (no BGP in home network)
- **DNS:** Relies on router's DNS (no Pi-hole integration yet)

---

## 12. External Dependencies

### Required Services

- **Home Router:** Static IP assignments for pi0-pi3
- **Internet:** Package downloads during Ansible runs
- **GitHub:** ArgoCD pulls from `jangroth/homekube-apps`

### Optional Integrations

- **Cloudflare Tunnel:** (Future) Expose services externally
- **External Secrets Operator:** (Future) Secret management

---

## 13. AI Assistant Decision Tree

### When Suggesting Changes

**Q: Does this change affect network CIDRs?**  
→ **Yes:** Reject unless user explicitly overrides (requires cluster rebuild)  
→ **No:** Proceed

**Q: Does this change component versions?**  
→ **Yes:** Check compatibility matrix (section 6), update `group_vars/all.yml`  
→ **No:** Proceed

**Q: Does this deploy a new app?**  
→ **Yes:** Add to `homekube-apps`, sync via ArgoCD  
→ **No:** Proceed

**Q: Does this require SSH access to nodes?**  
→ **Yes:** Suggest Ansible task or manual command with node IP  
→ **No:** Proceed

**Q: Is this a one-time operation?**  
→ **Yes:** Document as manual step, add to runbook  
→ **No:** Make it idempotent via Ansible

---

## 14. File Modification Rules

### Always Update Together

- `ansible/group_vars/all.yml` + relevant role `defaults/main.yml`
- ArgoCD app manifest + `kustomization.yaml` in parent wave directory
- Documentation in `doc/` if changing setup procedures

### Never Modify Directly

- `/etc/hosts` on control node (managed by playbook 01)
- NVMe mounts on Pis (managed by playbook 02)
- kubeadm config on pi0 (regenerate via playbook 04)

### Verify After Changes

```bash
# Ansible syntax
ansible-playbook --syntax-check <playbook.yml>

# Kubernetes manifests
kubectl --dry-run=server apply -f <manifest.yaml>

# Taskfile
task --list
```

---

## 15. Context Refresh Triggers

**Regenerate this file when:**

- Kubernetes version changes (major/minor)
- CNI or CSI replaced (e.g., Cilium → other)
- New node added/removed from cluster
- ArgoCD app structure changes
- Network CIDR changes (rare, requires cluster rebuild)

**Source of Truth for Regeneration:**

```bash
# Pull latest component versions
grep -E "(version|VERSION)" ansible/group_vars/all.yml

# Verify cluster state
kubectl get nodes -o wide
kubectl get pods -A

# Check ArgoCD apps
kubectl get applications -n argocd
```

---

**End of AI Context Map**  
For operational questions, see `doc/` and `ansible/README.md`.  
For code standards, see `.github/copilot-instructions.md`.
