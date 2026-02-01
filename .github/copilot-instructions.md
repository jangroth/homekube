# Copilot Instructions: homekube

You are assisting with **homekube**, a production Kubernetes cluster running on Raspberry Pi 5 hardware. This is Infrastructure-as-Code with real-world consequences. Never guess cluster state or network topology.

---

## Repository Purpose

Automated provisioning and management of a 4-node Kubernetes cluster using:
- **Ansible** for cluster bootstrapping and node configuration
- **ArgoCD** for GitOps-based application deployment
- **Taskfile** for common operational tasks

---

## Critical Architecture Facts

### Cluster Topology
- **Control Plane:** `pi0` (192.168.86.220 / 10.0.0.20)
- **Worker Nodes:** `pi1-pi3` (192.168.86.221-223 / 10.0.0.21-23)
- **Static IPs:** Always use the 192.168.86.x addresses for external access
- **Internal IPs:** Cilium uses 10.0.0.x for node-to-node communication

### Component Versions (Source of Truth: `ansible/group_vars/all.yml`)
- Kubernetes: **1.35.x**
- CNI: **Cilium 1.18.2** (not Calico, not Flannel)
- CSI: **Longhorn 1.9.1** (distributed block storage)
- CRI: **containerd 2.1.4** (not Docker)
- GitOps: **ArgoCD 9.1.2** (Helm chart version)

### Network Configuration (Non-Negotiable)
```yaml
Pod Network:     10.244.0.0/16  # kubeadm ClusterConfiguration
Service Network: 10.96.0.0/12   # kubeadm ClusterConfiguration
Cluster DNS:     10.96.0.10     # CoreDNS
```
**Do not suggest different CIDR ranges** without explicit user confirmation.

### Storage Architecture
- **Primary Storage:** NVMe drives on each Pi (via PCIe)
- **Longhorn:** Replicated block storage across nodes (default 3 replicas)
- **Storage Classes:** Use Longhorn storage classes, not `local-path` or `hostPath` for production workloads

---

## Ansible Playbook Execution Order

When the user references "cluster setup", this is the canonical sequence:

1. **`01-update-control-node.yml`** — Configures local machine (macOS) with SSH config, kubectl, k9s, Helm
2. **`02-prepare-pis.yml`** — OS-level Pi configuration, NVMe setup (semi-manual, includes bootloader steps)
3. **`03-setup-k8s-nodes.yml`** — Installs containerd, kubeadm, kubelet, kubectl
4. **`04-setup-k8s-control-plane.yml`** — Initialises Kubernetes control plane on pi0
5. **`05-setup-cni.yml`** — Installs Cilium CNI
6. **`06-setup-gitops.yml`** — Installs ArgoCD and bootstraps root application

**Idempotency:** Playbooks 1, 3-6 are idempotent. Playbook 2 requires manual steps (see `ansible/README.md`).

---

## ArgoCD Application Structure

### Repository: `jangroth/homekube-apps`
- **Root Application:** `applications/kustomization.yaml` (sync wave -2)
- **Init Wave (-1):** metallb, metrics-server
- **Apps Wave (1):** kubernetes-dashboard, test-lb
- **Custom Wave (2):** User-defined applications

### Deployment Pattern
All apps are deployed via ArgoCD. **Never suggest `kubectl apply -f`** for production workloads—add a new app manifest to `homekube-apps` instead.

---

## Code Standards and Skills

### Shell Scripts (`scripts/`)
- **Idempotency:** Scripts must handle repeated execution safely
- **Error Handling:** Always check exit codes, use `set -euo pipefail`
- **Ansible Integration:** Prefer Ansible tasks over standalone scripts for cluster operations
- **Output:** Provide human-readable output (e.g., IP detection, health checks)

### Ansible Roles
- **Variables:** All versions live in `ansible/group_vars/all.yml`
- **Inventory:** Never hardcode IPs—use `inventory/hosts` (pi0-pi3)
- **Tags:** Use tags for partial runs (e.g., `--tags update-only`)
- **Handlers:** Use handlers for service restarts, not inline `systemctl restart`

### Kubernetes Manifests
- **Namespace:** Always specify namespace explicitly (no `default` assumptions)
- **Resource Limits:** Set requests/limits for CPU and memory
- **Storage:** Use `storageClassName: longhorn` for PVCs
- **Networking:** MetalLB handles LoadBalancer services (IP pool: defined in metallb app)

### Task Automation (`Taskfile.yml`)
- **Working Directory:** Tasks run in `./ansible` by default (see `dir` field)
- **Dependencies:** Use `deps` for task chaining
- **Descriptions:** Every task must have a `desc` field

---

## High-Stakes Constraints

### Do Not Suggest:
1. **CNI Changes:** Cilium is the CNI. Do not propose Calico, Flannel, or Weave.
2. **Storage Migration:** Longhorn is the CSI. Do not suggest `local-path` or NFS for production.
3. **Manual `kubectl` Deploys:** Always route through ArgoCD for GitOps compliance.
4. **IP Range Changes:** Pod/Service networks are fixed (see above).
5. **Docker Commands:** This cluster uses `containerd` + `crictl`, not Docker CLI.

### Always Verify:
- **Ansible Variable Changes:** Check if updates are needed in both `group_vars/` and role defaults
- **Kubernetes Versions:** Compatibility between kubeadm, kubelet, Cilium, Longhorn
- **NVMe Paths:** `/dev/nvme0n1` is the standard path, but verify in playbooks before suggesting changes

---

## Operational Workflows

### Adding a New Application
1. Create app manifest in `homekube-apps/applications/wave-0X-*/`
2. Add to appropriate wave kustomization
3. Commit and push to `jangroth/homekube-apps`
4. ArgoCD auto-syncs (or use `argocd app sync <app-name>`)

### Updating Cluster Components
1. Update version in `ansible/group_vars/all.yml`
2. Re-run relevant playbook (e.g., `task setup-cni` for Cilium)
3. Verify with `kubectl get pods -A` or `k9s`

### Troubleshooting
- **Logs:** Use `kubectl logs -n <namespace> <pod>`
- **Node Issues:** SSH to pi via `ssh homekube@192.168.86.22X`
- **Cilium:** Use `cilium status` and `cilium connectivity test`
- **Longhorn:** Access UI via NodePort or Ingress

---

## File Navigation Hints

- **Architecture Diagrams:** `doc/images/`
- **Setup Documentation:** `doc/02_0X_*.md`
- **Secrets Patterns:** `secrets.md` (not version-controlled secrets, just patterns)
- **Manual Deployments:** `homekube-apps/manual/` (temporary/debugging)
- **Ansible Inventory:** `ansible/inventory/hosts`

---

## Language and Style

- **Australian English:** Use "synchronise", "initialise", "colour" in generated docs
- **Directness:** No "consultant speak"—provide actionable commands, not recommendations
- **Context:** Always reference which playbook/role/file you're modifying
- **Validation:** Suggest verification commands after changes (e.g., `kubectl get nodes`)

---

## When You Don't Know

If the user asks about cluster state (e.g., "which pods are running?"), do not infer from files. Instead:
1. Ask the user to run `kubectl get pods -A` or equivalent
2. Use the actual output to answer their question

**Never hallucinate cluster runtime state from static manifests.**
