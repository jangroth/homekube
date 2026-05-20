# TODO

## Done

- [x] AI workspace setup (CLAUDE.md, TODO, DECISIONS, repo structure)
- [x] Pin Python (3.12) and ansible-core (2.20.4) via uv in homekube-main
- [x] NVMe clone approach validated manually on pi0 (rsync, not dd/rpi-clone — see DECISION-005)

---

## Phase 0 — Tailscale Prereqs (one-time)

- [x] Generate reusable ephemeral auth key in Tailscale admin console
- [x] Store auth key in ansible-vault

---

## Phase 1 — All Pis Bootstrap (pi0–pi3, same process)

**Proven process:** Flash with Imager (current WiFi + `boot`/`boot` + SSH enabled), boot, `ssh boot@pi0.local`, install Tailscale with auth key, then add home + hotspot WiFi via nmcli.

- [x] pi0 — Tailscale joined, permanent WiFi configured
- [x] pi1 — Tailscale joined, permanent WiFi configured
- [x] pi2 — Tailscale joined, permanent WiFi configured
- [x] pi3 — Tailscale joined, permanent WiFi configured

Each pi steps:
- Flash SD card via Imager (current WiFi credentials, `boot`/`boot`, SSH on)
- Boot, SSH in: `ssh boot@pi0.local` (fall back to `arp -a` if mDNS not ready)
- `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --authkey=<key> --hostname=piN`
- Add permanent WiFi networks via nmcli (home, hotspot)

---

## Phase 2 — NVMe Automation (via Tailscale)

- [x] Encode validated NVMe setup process into ansible (`copy_mmc_to_nvme.yml`)
- [x] pi0 — migrated and verified booting from NVMe
- [x] pi1 — migrated and verified booting from NVMe
- [x] pi2 — migrated and verified booting from NVMe
- [x] pi3 — migrated and verified booting from NVMe
- [x] All four pis (pi0–pi3) boot from NVMe and reachable over Tailscale

---

## Phase 3 — Bootstrap Provisioning (Ansible)

- [x] Implement spec 003: inventory refactor + node provisioning automation (see commit 63bf9c8)
  - Removed `ip_addresses_external`; `group_vars/all_nodes.yml` sets `homekube` as default user
  - Rewrote SSH config + known_hosts tasks to use `groups['all_nodes']` (MagicDNS, no IPs)
  - Fixed `create_user_account.yml`: probe before falling back to `boot` creds; lock boot user
  - Added `sync_authorized_keys` + `verify_sshd_config` for idempotent no-tag re-runs
  - `disable_swap.yml` → `configure_swap.yml`: 4 GiB swapfile instead of disabling swap
  - Removed `install_tailscale` from k8s-node role; added `configure_etc_hosts` for inter-node /etc/hosts
- [x] Add darth + kylo public keys to `pub_keys/` (human checkpoint — see spec 003)
- [x] Run `20-configure-darth.yml` — configures darth (SSH config, known_hosts, tooling)
- [x] Run `21-provision-pis.yml --tags init` — creates `homekube` user, deploys keys, configures OS, swap
- [x] Run `21-provision-pis.yml` — idempotency check (zero changes)
- [x] Run `22-k8s-nodes.yml` — k8s prerequisites on all nodes
- [x] Verify `ssh homekube@pi0` works from darth and kylo over Tailscale

---

## Phase 4 — Kubernetes Install

- [x] Implement spec 004: Phase 4 playbooks (`30-k8s-control-plane.yml`, `31-k8s-workers.yml`, `40-cni.yml`)
  - `kubeadm-config.yaml`: fixed swap config, added node-ip/controlPlaneEndpoint/resolvConf, removed stray JoinConfiguration
  - `k8s-control-plane` role: added `init_control_plane.yml` (idempotent kubeadm init) and `setup_kubeconfig.yml` (fetch + rewrite to darth)
  - New `k8s-worker` role: token/CA-hash query from pi0, join, verify
  - `cilium-helm-values.yaml`: explicit API server IP, `devices: eth0`, vxlan routing
  - `host_vars/pi*.yml` and `group_vars` additions for switch IPs and network CIDRs
- [x] Run `30-k8s-control-plane.yml` — kubeadm init on pi0 (pi0 NotReady, awaiting CNI)
- [x] Run `31-k8s-workers.yml` — join worker nodes (pi1, pi2, pi3); all 4 nodes present, NotReady awaiting CNI
- [x] Run `40-cni.yml` — Cilium 1.19.4 installed; pi0 confirmed Ready
- [x] Verify cluster health: all 4 nodes Ready (pi0–pi3), system pods running

---

## Phase 5 — GitOps & Apps

- [x] Run `50-gitops.yml` — ArgoCD 9.5.14 installed, root-app created
- [ ] Verify ArgoCD is up and syncing homekube-apps (metrics-server + argocd-config active)
- [ ] Verify metrics-server healthy (`kubectl top nodes`)
- [ ] Incrementally re-enable apps in kustomization.yaml (Longhorn, MetalLB, then observability stack)
- [ ] Verify all apps healthy: MetalLB, metrics-server, Longhorn, Prometheus, Grafana, Loki

---

## Documentation (update each phase as it's completed)

- [x] Restructure `homekube-main/docs/` — new file naming scheme, remove stale content
- [x] `01_bootstrap.md` — Imager + Tailscale + nmcli process
- [x] `02_nvme.md` — rewritten to show Ansible steps vs manual checkpoints
- [x] `03_ansible.md` — preconditions, playbook sequence, kylo SSH stanza, verification
- [ ] `04_kubernetes.md` — fill in after Phase 4
- [ ] `05_gitops.md` — fill in after Phase 5

---

## Backlog

- [ ] Revisit `display_dependencies` task in k8s-node role — current approach may have a better solution

- [ ] Investigate OOM root cause from previous run (kernel logs, events)
- [ ] Review all component versions against latest releases
- [ ] Set up Claude SSH autonomy (trust policy update)
- [x] Clean up stale links in `homekube-main/README.md` (resolved in earlier session)
- [ ] Fix `enable_pciex.yml`: `file: state: touch` always reports changed; should be `state: file` (existence check) or removed (blockinfile will surface missing-file errors clearly)
- [ ] Review need for kube-bench: assess whether it's worth keeping in the `k8s-control-plane` role and what to do with its output
