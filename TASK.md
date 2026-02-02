# TASK: Baseline Cluster Rebuild - Debian Trixie & Kubernetes 1.35

**Branch:** `baseline-cleanup`
**Created:** 1 February 2026
**Status:** In Progress
**Priority:** High

---

## Objective

Establish a clean baseline cluster configuration where all Raspberry Pi nodes run the latest stable software stack, ensuring a reproducible and well-documented foundation for future development.

### Success Criteria

- ✅ All 4 nodes (pi0-pi3) running **Raspberry Pi OS Lite (Debian Trixie)** with swap enabled
- ✅ Kubernetes **v1.35.x** installed and operational
- ✅ Latest stable versions of CRI/CSI/CNI without compatibility issues:
  - **containerd** (CRI) - latest stable
  - **Longhorn** (CSI) - latest stable
  - **Cilium** (CNI) - latest stable
- ✅ All Ansible playbooks execute idempotently without errors
- ✅ Cluster passes basic health checks (pods running, storage accessible, networking functional)
- ✅ Documentation updated to reflect current versions and any configuration changes

---

## Background

The current cluster may have accumulated configuration drift or be running outdated package versions. This task resets the cluster to a known-good baseline state, using the latest stable software versions and ensuring all automation scripts work correctly.

### Current State (Pre-Task)

- Kubernetes: **v1.34.1** (per README.md)
- OS: Raspberry Pi OS Lite 64-bit (Debian Bookworm)
- Swap: Disabled on all nodes
- Package versions: May vary across nodes

### Target State (Post-Task)

- Kubernetes: **v1.35.x** (latest stable patch release)
- OS: Raspberry Pi OS Lite (Debian Trixie) - consistent across all nodes
- Swap: **Enabled** on all nodes (as per new requirement)
- Package versions: Latest stable, version-locked in Ansible variables
- All system packages updated to latest

---

## Prerequisites (Manual Steps)

⚠️ **These tasks MUST be completed manually before running Ansible playbooks:**

1. **NVMe Setup** (Physical Access Required)
   - Ensure NVMe drives are physically installed on all nodes
   - Boot each node and verify NVMe is detected: `lsblk`
   - Format and mount NVMe drives if not already done
   - Configure fstab entries for persistent mounting

2. **OS Installation** (If Clean Install Required)
   - Flash Raspberry Pi OS Lite (Debian Trixie) to SD cards or boot devices
   - Boot each node and complete initial setup (locale, timezone, etc.)
   - Enable SSH on all nodes
   - Set hostnames: pi0, pi1, pi2, pi3
   - Verify static IP assignments match inventory:
     - pi0: 192.168.86.220
     - pi1: 192.168.86.221
     - pi2: 192.168.86.222
     - pi3: 192.168.86.223

3. **SSH Access**
   - Ensure control node can SSH to all nodes without password (SSH keys configured)
   - Verify connectivity: `ansible all_nodes -m ping`

---

## Implementation Steps

### Phase 1: Version Discovery & Planning

- [ ] Check latest stable versions:
  - Kubernetes 1.35.x latest patch release
  - containerd latest stable (2.x series)
  - runc latest stable (1.x series)
  - Cilium latest stable (1.x series)
  - Longhorn latest stable (1.x series)
  - containernetworking-plugins latest stable

- [ ] Review Ansible role variables for version specifications:
  - `ansible/roles/k8s-node/defaults/main.yml`
  - `ansible/roles/kubeadm/defaults/main.yml`
  - `ansible/roles/cilium/defaults/main.yml`
  - Other relevant role defaults

### Phase 2: OS Baseline Configuration

- [ ] Verify OS version on all nodes (should be Debian Trixie)
  ```bash
  ansible all_nodes -m shell -a "cat /etc/os-release"
  ```

- [ ] Check swap status on all nodes
  ```bash
  ansible all_nodes -m shell -a "swapon --show"
  ```

- [ ] Update Ansible playbooks to ensure swap is enabled (if not default)
  - Update `02-prepare-pis.yml` or relevant role
  - Add swap configuration tasks if missing

- [ ] Run OS preparation playbook:
  ```bash
  cd ansible
  ansible-playbook 02-prepare-pis.yml
  ```

### Phase 3: Update Package Versions

- [ ] Update version variables in Ansible roles:
  - Kubernetes to 1.35.x
  - containerd to latest stable
  - runc to latest stable
  - CNI plugins to latest stable

- [ ] Review and update component installation tasks:
  - `ansible/roles/k8s-node/tasks/containerd.yml`
  - `ansible/roles/kubeadm/tasks/main.yml`
  - Any download/installation scripts

### Phase 4: Cluster Deployment

- [ ] Run full cluster setup sequence:
  ```bash
  cd ansible
  # 1. Update control node
  ansible-playbook 01-update-control-node.yml

  # 2. Prepare Pi nodes
  ansible-playbook 02-prepare-pis.yml

  # 3. Setup K8s nodes (CRI/runtime)
  ansible-playbook 03-setup-k8s-nodes.yml

  # 4. Initialize control plane
  ansible-playbook 04-setup-k8s-control-plane.yml

  # 5. Setup CNI (Cilium)
  ansible-playbook 05-setup-cni.yml

  # 6. Setup GitOps (ArgoCD)
  ansible-playbook 06-setup-gitops.yml
  ```

- [ ] Verify playbook execution:
  - All tasks complete successfully
  - No ERROR or FAILED states
  - CHANGED tasks are expected first run, ok on subsequent runs

### Phase 5: Cluster Verification

- [ ] Verify cluster status:
  ```bash
  kubectl get nodes -o wide
  kubectl get pods -A
  kubectl version
  ```

- [ ] Check all nodes are Ready:
  ```bash
  kubectl get nodes
  # All should show STATUS=Ready
  ```

- [ ] Verify CNI (Cilium):
  ```bash
  kubectl get pods -n kube-system | grep cilium
  cilium status
  ```

- [ ] Verify CSI (Longhorn):
  ```bash
  kubectl get pods -n longhorn-system
  kubectl get storageclass
  ```

- [ ] Test pod networking:
  ```bash
  kubectl run test-pod --image=nginx --rm -it -- /bin/sh
  # Verify pod can reach internet and other pods
  ```

- [ ] Test persistent storage:
  ```bash
  # Create test PVC and pod using Longhorn
  # Verify volume provisioning works
  ```

### Phase 6: Documentation Update

- [ ] Update [README.md](homekube-main/README.md) with new versions:
  - Kubernetes version
  - containerd version
  - runc version
  - Cilium version
  - Longhorn version
  - CNI plugins version

- [ ] Update [AI-CONTEXT.md](homekube-main/AI-CONTEXT.md):
  - Component versions in Section 1-4
  - Any architectural changes
  - New configuration parameters

- [ ] Update [PRD.md](homekube-main/PRD.md) if scope changed

- [ ] Document swap configuration in relevant docs:
  - Update `doc/02_01_node-configuration.md` or create new section
  - Explain why swap is enabled (if non-standard for K8s)

- [ ] Update Ansible role documentation:
  - Any new role variables
  - Changed default values
  - New tasks added

---

## Validation Checklist

Before marking this task complete, verify:

- [ ] All nodes show correct OS version: `cat /etc/os-release`
- [ ] All nodes have swap enabled: `swapon --show`
- [ ] Kubernetes version is 1.35.x: `kubectl version --short`
- [ ] All nodes are Ready: `kubectl get nodes`
- [ ] All system pods are Running: `kubectl get pods -n kube-system`
- [ ] Cilium is healthy: `cilium status`
- [ ] Longhorn is operational: `kubectl get pods -n longhorn-system`
- [ ] Can create and mount PVCs: Test with sample workload
- [ ] ArgoCD is running: `kubectl get pods -n argocd`
- [ ] Ansible playbooks are idempotent: Second run shows mostly "ok" states
- [ ] All documentation is updated with current versions
- [ ] Git commit history is clean with descriptive messages

---

## Rollback Plan

If cluster becomes unstable:

1. **Document Issues:**
   - Capture error messages: `kubectl get events -A`
   - Save logs: `kubectl logs <pod-name> -n <namespace>`
   - Note which step failed

2. **Revert to Previous State:**
   - If Ansible playbook failed mid-run, re-run specific failed tasks
   - If cluster is broken, may need to reset: `kubeadm reset` on all nodes
   - Restore from git commit before version updates

3. **Recovery Options:**
   - Downgrade specific component (e.g., K8s 1.35 → 1.34)
   - Check compatibility matrix for CRI/CNI/CSI versions
   - Review upstream changelogs for breaking changes

---

## Notes & Observations

### Design Decisions

- **Swap Enabled:** Kubernetes 1.22+ supports swap with cgroup v2. Required for [specific use case - document why]
- **Version Selection:** Using latest stable releases for best security and features
- **Debian Trixie:** Latest Raspberry Pi OS baseline for long-term support

### Known Issues / Risks

- Kubernetes 1.35 may have breaking changes from 1.34 (review changelog)
- Cilium/Longhorn may need configuration updates for K8s 1.35
- Swap + Kubernetes may require specific kubelet configuration
- NVMe manual setup is error-prone; document carefully

### Future Improvements

- Automate NVMe detection and partitioning in Ansible
- Add automated cluster health checks post-deployment
- Create backup/restore procedures before major upgrades
- Consider staging environment for testing version updates

---

## References

- [Kubernetes 1.35 Release Notes](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.35.md)
- [containerd Releases](https://github.com/containerd/containerd/releases)
- [Cilium Documentation](https://docs.cilium.io/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Raspberry Pi OS Documentation](https://www.raspberrypi.com/documentation/)
- Current cluster docs: [AI-CONTEXT.md](homekube-main/AI-CONTEXT.md), [PRD.md](homekube-main/PRD.md)

---

## Timeline

**Estimated Effort:** 4-6 hours

- Phase 1 (Planning): 30 minutes
- Phase 2 (OS Baseline): 1 hour
- Phase 3 (Version Updates): 1 hour
- Phase 4 (Deployment): 1-2 hours
- Phase 5 (Verification): 1 hour
- Phase 6 (Documentation): 30-60 minutes

**Dependencies:** Manual NVMe setup must be complete before Phase 4

---

**Last Updated:** 1 February 2026
