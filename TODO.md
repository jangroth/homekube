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
- [x] Verify ArgoCD is up and syncing homekube-apps (metrics-server + argocd-config active)
- [x] Verify metrics-server healthy (`kubectl top nodes` — all 4 nodes reporting)
- [ ] Phase 5 production setup — see spec 005
  - [x] Bump existing ArgoCD chart 9.5.14 → 9.5.15 — confirmed running 9.5.15 (chart `argo-cd-9.5.15`, app `v3.4.2`)
  - [x] Ansible prerequisites — `/storage` partition (851.5 GiB, nvme0n1p3) created on all 4 nodes; `10-nvme.yml` updated to automate for future provisioning; `open-iscsi` was already present
  - [ ] Etcd snapshot systemd timer on pi0 (daily → S3, 14-day retention) — deferred
  - [ ] Wave -1:
    - [x] sealed-secrets chart 2.18.6 / app 0.37.0 — ArgoCD app manifest deployed to homekube-apps
    - [x] **Validate sealed-secrets**: `kubeseal --fetch-cert` → cert saved to password manager; round-trip test passed
    - [x] cert-manager chart v1.20.2 + `homekube-ca` ClusterIssuer — deployed, all pods Running, `ClusterIssuer/homekube-ca` Ready=True
      - [x] **Human step:** export CA cert → trust on darth (`sudo security add-trusted-cert ...`)
      - [x] **Human step:** save `homekube-ca-secret` (full YAML, cert + key) to password manager
    - [x] kubelet-csr-approver chart 1.2.14 — deployed; `bypassDnsResolution: true` required; `--node-ip` set on all nodes via Ansible (see DECISION-028/029)
    - [x] ~~metallb chart 0.16.0 + IPAddressPool + L2Advertisement~~ — **superseded by spec 006** (DECISION-031). Replaced with Cilium-native LB-IPAM + L2 announcements (2026-06-22):
      - [x] **Step 0** — pre-flight: confirmed `CiliumLoadBalancerIPPool` = `v2`, `CiliumL2AnnouncementPolicy` = `v2alpha1`
      - [x] **Step 1** — MetalLB removed (GitOps prune); CRDs manually deleted
      - [x] **Step 2** — Cilium values: `devices: "eth0,wlan0,tailscale0"` + l2announcements + rate limit; rolled out
      - [x] **Step 3** — `cilium-lb/` (pool.yaml + l2policy.yaml) + Application deployed via ArgoCD
      - [x] **Step 4** — validated: VIP `192.168.86.241` assigned; Tailscale 36/36 over 3 min ✓; Wi-Fi intermittent (see Backlog)
      - [x] **Step 5** — docs finalized (spec 006 §7); DECISION-032 recorded; CHANGELOG updated
      - Note: Tailscale route `192.168.86.240/28` unchanged (pool stays on Wi-Fi subnet)
    - [x] Move ArgoCD service from NodePort :30000 to LoadBalancer `192.168.86.241:80` (DECISION-033)
    - [x] longhorn chart 1.11.2 (bump from 1.9.1) + UI exposed via LoadBalancer `192.168.86.242:80`; runs on pi1/pi2/pi3 only — pi0 excluded (etcd SPOF, shared NVMe, see spec 005 §5)
  - [x] Validate wave -1 (capabilities 2–5 acceptance criteria)
  - [ ] Wave 1: MinIO upstream chart, longhorn-extras, kube-prometheus-stack chart 85.3.0, Loki chart 7.0.0 (v6 → v7 values-schema rewrite), Alloy chart 1.8.1 (new manifest, replaces Promtail)
  - [ ] Validate wave 1 (capabilities 6–8); confirm Telegram alert receiver delivers a test alert
  - [ ] Wave 2: Google OAuth client → sealed-secret → Dex chart 0.24.0 / app 2.44.0 → ArgoCD + Grafana OIDC config
  - [ ] Validate wave 2 (capability 9)
  - [ ] Wave 3: verify Cilium `kubeProxyReplacement` (separate scheduled change if flip needed) → Istio 1.30.0 + Kiali (opt-in namespaces only) → external S3 + sealed AWS creds → Velero chart 12.0.1 / app 1.18.0 (CSI plugin) + Longhorn backup target
  - [ ] Validate wave 3 (capabilities 10–11); document etcd restore drill in `homekube-main/docs/restore-etcd.md`

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

- [ ] **Consolidate documentation** — once all specs (005–007+) are implemented, do a pass to merge the scattered component-version tables, outdated README sections, and phase docs into a coherent state. `homekube-main/README.md` Components table is a known stale spot.

- [ ] **Investigate Wi-Fi → LB VIP flakiness** — Cilium L2 announcement path via `wlan0` (pi2 as L2 leader) is intermittently unreliable: some devices/attempts succeed, others time out. Tailscale path is solid (36/36). Likely causes: brief Cilium BPF reload windows during endpoint regeneration, wlan0 dual-use (internet + LB), or AP-level wireless variability. Investigate Cilium endpoint regeneration frequency and whether pinning the L2 leader or reducing endpoint churn improves stability. See DECISION-032.

- [ ] Revisit `display_dependencies` task in k8s-node role — current approach may have a better solution

- [ ] Investigate OOM root cause from previous run (kernel logs, events)
- [x] Review all component versions against latest releases (done 2026-05-23 — Version Policy + Pinned Versions table in spec 005)
- [ ] Set up Renovate (or equivalent) against `homekube-apps` to surface chart-version PRs automatically — operationalises the Version Policy (DECISION-017)
- [ ] Set up Claude SSH autonomy (trust policy update)
- [x] Clean up stale links in `homekube-main/README.md` (resolved in earlier session)
- [ ] Fix `enable_pciex.yml`: `file: state: touch` always reports changed; should be `state: file` (existence check) or removed (blockinfile will surface missing-file errors clearly)
- [ ] Review need for kube-bench: assess whether it's worth keeping in the `k8s-control-plane` role and what to do with its output
- [ ] Build a Claude Code skill for tracking component version updates (surfaces new chart/image releases against pinned versions)
- [ ] **Idea: extend cluster with AWS spot instances** — join ARM spot nodes (t4g family, matches Pi arch) to the existing control plane over Tailscale. Approach: spin up instance → install Tailscale → `kubeadm join` using pi0's Tailscale IP. Use Karpenter for spot lifecycle (handles 2-min interruption drain). Key challenges: control plane SPOF (pi0 down = AWS nodes orphaned), cross-environment latency (20–100ms), AWS egress cost for cross-boundary pod traffic. Explore as burst capacity or for workloads needing more RAM/CPU than Pis offer.
