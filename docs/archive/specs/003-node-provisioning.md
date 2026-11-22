# Spec 003 — Node Provisioning

**Status:** Done
**Goal:** Fully automated provisioning of all four pis, ready for `kubeadm init`. Covers Ansible-based OS configuration, swap, k8s prerequisites, and SSH access from darth and kylo — without any hardcoded IPs or DHCP dependency.

---

## Problem

Phases 1 and 2 are complete: all pis boot from NVMe and are reachable over Tailscale. The `boot` user is still the only login on each pi. Phase 3 must:

1. Wire up Ansible to manage pis over Tailscale (not DHCP IPs)
2. Provision the `homekube` user with SSH access from both darth and kylo
3. Disable the `boot` user and password auth once `homekube` is established
4. Configure swap in a way that is compatible with kubernetes
5. Prepare k8s prerequisites on all nodes (cgroups, kernel params, containerd, k8s packages)

The current codebase has several problems to address before automation is viable:

- `group_vars/raspberry_pis.yml` contains `ip_addresses_external` (hardcoded DHCP IPs, unreliable) and a vaulted `tailscale_auth_key` no longer needed (Tailscale already up)
- The `control-node` role writes `/etc/hosts` and `~/.ssh/config` using those DHCP IPs; `update_known-hosts.yml` iterates over `ip_addresses_external` in four separate loops (so deleting the var breaks the task)
- `update_etc_hosts.yml` writes to **darth's** `/etc/hosts` — useless, since darth isn't on the 10.0.0.x plane
- Ansible inventory has no explicit connection settings (relies on SSH config being pre-configured)
- All keys in `pub_keys/` are stale (generated on old SD card installs, not current NVMe systems); darth's and kylo's control-node keys are outdated
- Only darth's key is deployed; kylo has no access
- `create_user_account.yml` unconditionally sets `ansible_user=boot` / `ansible_ssh_pass=boot`, breaking re-runs after password auth is disabled
- `disable_swap.yml` removes swap entirely; k8s supports swap and the cluster should use it
- `roles/raspberry-pi/tasks/main.yml` only has tasks gated on `init`/`nvme_pre`/`nvme_post` tags — an untagged invocation is a no-op
- `install_tailscale.yml` is imported by the `k8s-node` role even though Tailscale is already up

---

## Preconditions

Manual steps that must complete before Phase 3 begins. These cannot be automated.

- [x] **Darth keypair exists:** `ls ~/.ssh/id_darth_homekube` succeeds; if not, `ssh-keygen -t ed25519 -f ~/.ssh/id_darth_homekube -C "darth@homekube"`
- [x] **Kylo keypair exists:** on kylo, `ssh-keygen -t ed25519 -f ~/.ssh/id_kylo_homekube -C "kylo@homekube"`
- [x] **Both public keys committed** to `roles/raspberry-pi/files/pub_keys/`: `id_darth_homekube.pub` and `id_kylo_homekube.pub`
- [x] **Tailscale MagicDNS resolves from darth:** `tailscale status | grep pi0` returns a tailnet IP; `ssh boot@pi0` works (password auth)
- [x] **`pub_keys/` is empty of stale node keys** (already done; phase 3 regenerates `pi0.pub`–`pi3.pub`)

---

## Acceptance Criteria

- [x] `ansible-playbook 20-configure-darth.yml` succeeds
- [x] After (1), `ssh homekube@pi0` (and pi1–pi3) works from darth using `~/.ssh/config` with MagicDNS hostnames (no IPs), with no host-key prompt
- [x] `ansible-playbook 21-provision-pis.yml --tags init` succeeds on all 4 pis from a clean (boot-user-only) state
- [x] Re-running `ansible-playbook 21-provision-pis.yml` (no tags) after the init run completes idempotently — zero changes on the second run
- [x] `pub_keys/` contains exactly 6 fresh keys: `id_darth_homekube.pub`, `id_kylo_homekube.pub`, `pi0.pub`–`pi3.pub` — all generated post-NVMe-migration
- [x] `ssh homekube@pi0` works from kylo (key-based, over Tailscale); password auth on pis is disabled (`grep PasswordAuthentication /etc/ssh/sshd_config` → `no`)
- [x] `boot` user is locked on all pis (`sudo passwd -S boot` shows `L`)
- [x] All 4 pis have a swapfile active (`swapon --show` shows `/var/swap.img`, 4 GiB)
- [x] `ansible-playbook 22-k8s-nodes.yml` succeeds on all 4 nodes
- [x] `sudo kubeadm init --dry-run --ignore-preflight-errors=Swap` on pi0 completes with no FATAL preflight errors (Swap preflight ignored deliberately; kubelet swap config is a Phase 4 deliverable — see section 4)
- [x] No hardcoded DHCP IPs remain in any Ansible file used for management access

---

## Out of Scope

- `kubeadm init` and `kubeadm join` (Phase 4)
- Kubelet swap configuration (`failSwapOn: false`, `memorySwap.swapBehavior: LimitedSwap`) — provided to kubeadm in Phase 4 via `kubeadm-config.yaml` and `JoinConfiguration`
- CNI, GitOps, monitoring (later phases)
- Running Ansible from kylo (kylo gets SSH access; darth remains the control node)
- Re-installing Tailscale on pis (already done in Phases 1–2; the `install_tailscale.yml` import is removed from the k8s-node role — see section 6)

---

## Approach

### 1. Refactor: Remove `ip_addresses_external`, lean on Tailscale MagicDNS

`group_vars/raspberry_pis.yml` has `ip_addresses_external` (192.168.86.x) — DHCP, unreliable — delete it. Keep `ip_addresses_internal` (10.0.0.x): static switch IPs used by k8s itself (node IPs, etcd peers). Keep `tailscale_auth_key` (vaulted): retained for potential future re-provisioning.

Inter-node `/etc/hosts` resolution belongs **on the pis** (k8s plane), not on darth. Darth uses MagicDNS exclusively.

**Files to change:**

| File | Action | Notes |
|------|--------|-------|
| `ansible/group_vars/raspberry_pis.yml` | edit | Remove `ip_addresses_external`; keep `tailscale_auth_key` |
| `ansible/group_vars/all_nodes.yml` | **new** | `ansible_user: homekube`, `ansible_ssh_private_key_file: ~/.ssh/id_darth_homekube` |
| `ansible/roles/control-node/tasks/update_etc_hosts.yml` | **delete** | Darth isn't on 10.0.0.x; MagicDNS handles darth → pi resolution |
| `ansible/roles/control-node/tasks/main.yml` | edit | Drop the `update_etc_hosts.yml` import |
| `ansible/roles/control-node/tasks/update_ssh_config.yml` | rewrite | MagicDNS hostnames (`HostName pi0`); drop duplicate `Host <ip>` stanzas; add `StrictHostKeyChecking accept-new` |
| `ansible/roles/control-node/tasks/update_known-hosts.yml` | rewrite | Iterate over inventory group `all_nodes` in a single loop; no IP variant |
| `ansible/roles/k8s-node/tasks/configure_etc_hosts.yml` | **new** | Write internal-IP `/etc/hosts` on the pis using existing `hosts.j2` template; loop over `ip_addresses_internal` |
| `ansible/roles/k8s-node/tasks/main.yml` | edit | Import the new `configure_etc_hosts.yml` |

### 2. Inventory: explicit connection settings via `group_vars`

`hosts.ini` stays minimal. Connection config lives in `group_vars/all_nodes.yml`:

```yaml
ansible_user: homekube
ansible_ssh_private_key_file: ~/.ssh/id_darth_homekube
```

MagicDNS resolves `pi0`–`pi3` when Tailscale is active on darth — no `ansible_host` override needed. The `init` tag (first-run bootstrap) falls back to `boot`/`boot` only when the `homekube` user does not yet exist; see section 3.

### 3. SSH keys + user bootstrap

All keys in `roles/raspberry-pi/files/pub_keys/` were deleted (stale). Phase 3 regenerates them.

**Fix `create_user_account.yml`:** the existing unconditional `set_fact` of `ansible_user=boot` / `ansible_ssh_pass=boot` breaks every re-run after password auth is disabled. Gate it with a probe.

```yaml
- name: Probe whether homekube user already exists
  ansible.builtin.raw: id homekube
  register: homekube_user_probe
  ignore_errors: true
  changed_when: false

- name: Use bootstrap credentials only if homekube does not exist
  set_fact:
    ansible_user: boot
    ansible_ssh_pass: boot
  no_log: true
  when: homekube_user_probe.rc != 0
```

The probe runs as whatever the inventory says (`homekube`). On a clean pi the probe fails (homekube doesn't exist yet) and we fall back to `boot`/`boot`. On a re-run, the probe succeeds and the override is skipped.

**Ordering inside `create_user_account.yml`:** deploy darth's key into `authorized_keys` **before** calling `disable_password_auth.yml`. Otherwise a partial failure between those two steps leaves the pi reachable only via physical/serial console.

**Workflow:**

1. Preconditions checklist complete (darth + kylo pubkeys in `pub_keys/`)
2. `ansible-playbook 21-provision-pis.yml --tags init` — first run: connects as `boot`, creates `homekube`, generates a node keypair, fetches `pub_keys/piN.pub` back, deploys all `pub_keys/*.pub` to `authorized_keys`, disables password auth, locks `boot`
3. After the run, `pub_keys/` contains 6 files: `id_darth_homekube.pub`, `id_kylo_homekube.pub`, `pi0.pub`–`pi3.pub`. Commit the regenerated node keys
4. `ansible-playbook 21-provision-pis.yml` (no tags) — idempotent re-run; should report zero changes

For kylo's `~/.ssh/config`: document the minimal stanza in `homekube-main/docs/03_ansible.md`. One-time manual step (we are not running Ansible from kylo).

### 4. Swap: configure, not disable

Kubernetes [supports swap on Linux](https://kubernetes.io/docs/concepts/architecture/nodes/#swap-memory) (NodeSwap feature, GA in 1.30+). Pi 5 with 8 GB RAM + 1 TB NVMe benefits from swap: OOM has already been observed on pi0 (control plane) when image pulls + `kubeadm init` exhausted physical RAM.

**Rename** `roles/k8s-node/tasks/disable_swap.yml` → `configure_swap.yml`. New behaviour:

1. Remove `dphys-swapfile` (the old dynamic swapper) and explicitly delete `/var/swap` (its default path — a stale 100 MiB file is harmless but messy)
2. Create a fixed swapfile: `fallocate -l {{ swap_size_gb }}G /var/swap.img`
3. `chmod 600 /var/swap.img`, `mkswap /var/swap.img`, `swapon /var/swap.img`
4. Persist via `/etc/fstab` entry
5. Expose size as a variable in `group_vars/all.yml`:

   ```yaml
   swap_size_gb: 4
   ```

   Reference as `{{ swap_size_gb }}` everywhere it appears (fallocate, fstab comment).

**Ordering:** move `configure_swap.yml` to run **after** `install_kube_packages.yml` in `roles/k8s-node/tasks/main.yml`. Kubelet won't actually do anything before `kubeadm init/join` writes `/var/lib/kubelet/config.yaml`, but with `failSwapOn: true` defaulted, the systemd unit crashloops noisily until Phase 4. Enabling swap last keeps journalctl quieter and avoids confusion if anyone inspects the node mid-phase.

**Kubelet swap config — single source of truth (Phase 4):** the canonical knob is `KubeletConfiguration`, not `/etc/default/kubelet`. Phase 4 will provide it through:
- `roles/k8s-control-plane/files/kubeadm-config.yaml` — add a `KubeletConfiguration` section with `failSwapOn: false` and `memorySwap.swapBehavior: LimitedSwap`
- A worker-side `JoinConfiguration` patch (new file in Phase 4)

Phase 3 deliberately leaves kubelet swap config alone. This is why acceptance criterion `kubeadm init --dry-run` uses `--ignore-preflight-errors=Swap`.

### 5. k8s node prerequisites (`22-k8s-nodes.yml`)

No structural changes — run the existing playbook after the above refactors. Verify these tasks pass cleanly:

- `configure_cgroups.yml` — cgroup v2, memory cgroup enabled in `cmdline.txt`
- `configure_kernel.yml` — sysctl params for bridge netfilter and IP forwarding
- `configure_network_kernel.yml` — **currently empty file**; either populate (overlay + br_netfilter modules) or remove the import from `main.yml`
- `install_container_runtime.yml` — containerd installed and running
- `install_kube_packages.yml` — kubeadm, kubelet, kubectl at pinned version

### 6. Additional cleanup

- **Remove `install_tailscale.yml` from the `k8s-node` role.** Tailscale lifecycle belongs to phases 1–2, not k8s prereqs. Drop the import in `roles/k8s-node/tasks/main.yml`.
- `configure_nvme.yml` in the `raspberry-pi` role is gated on `nvme_pre`/`nvme_post` tags — leave as-is.
- **Make untagged `21-provision-pis.yml` meaningful.** Update `roles/raspberry-pi/tasks/main.yml` to add untagged idempotent tasks (authorized_keys sync, sshd hardening verification) so re-runs without `--tags init` produce real validation. Acceptance criterion "zero-change idempotent run" depends on this.

---

## Playbook Run Order

On darth, from `homekube-main/ansible/`:

| Step | Command | Expected state after |
|------|---------|---------------------|
| 1 | `ansible-playbook 20-configure-darth.yml` | Darth's `~/.ssh/config` has pi0–pi3 stanzas using MagicDNS; `~/.ssh/known_hosts` populated; brew packages installed |
| 2 | `ansible-playbook 21-provision-pis.yml --tags init` | `homekube` user exists on all pis; `pub_keys/` has 6 files; password auth disabled; `boot` locked |
| 3 | `ansible-playbook 21-provision-pis.yml` | Zero-change idempotent run (sanity check) |
| 4 | `ansible-playbook 22-k8s-nodes.yml` | containerd + kubelet/kubeadm/kubectl installed; cgroups + sysctl + swap configured |
| 5 | `ssh homekube@pi0 "sudo kubeadm init --dry-run --ignore-preflight-errors=Swap"` | Exits 0; no FATAL preflight errors |

---

## Verification

Concrete commands to confirm acceptance criteria after step 5:

```bash
# Connectivity
ansible all -m ping                                       # all green
ssh homekube@pi0 hostname                                 # → pi0

# User + auth state
ansible all -b -a 'passwd -S boot'                        # "L" status on all
ansible all -b -a 'grep PasswordAuthentication /etc/ssh/sshd_config'
                                                          # "PasswordAuthentication no"

# Swap
ansible all -a 'swapon --show'                            # /var/swap.img 4G

# K8s prereqs
ansible all -a 'kubelet --version'                        # matches kubernetes_version
ansible all -a 'containerd --version'                     # matches containerd_version
ansible all -b -a 'systemctl is-active containerd'        # active

# Key inventory
ls roles/raspberry-pi/files/pub_keys/                     # 6 files, expected names
```

---

## Rollback / Recovery

Phase 3 is mostly forward-only (key generation, package installs), but several failure modes are worth pre-empting.

| Failure | Recovery |
|---------|----------|
| `--tags init` fails midway, `homekube` user partially created | Re-run — the probe in `create_user_account.yml` detects existing `homekube` and skips bootstrap creds; `authorized_key` and other modules are idempotent |
| `--tags init` fails after password auth disabled but before darth's key reached `authorized_keys` | Physical/serial console only. Mitigation: ordering rule in section 3 — keys deployed before `disable_password_auth.yml` |
| Swap on + kubelet crashloops noisily | Harmless until Phase 4 (kubelet has no work yet). If urgent, `swapoff /var/swap.img` and comment fstab; re-run swap task after fixing |
| pi0 unreachable post-bootstrap | Tailscale admin console → check device status; fall back to switch IP (10.0.0.20) from a machine on that plane |
| Wrong/missing keys deployed | Update `pub_keys/`, re-run `21-provision-pis.yml` (untagged) — `authorized_key` task syncs |

**pi0 is the highest-risk node** (control plane, all later phases depend on it). Test the full flow on pi3 first if uncertain.

---

## Open Questions

None outstanding.
