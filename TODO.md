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

- [ ] Update ansible inventory to use Tailscale hostnames
- [ ] Add Tailscale role to `02-prepare-pis.yml`
- [ ] Verify darth's SSH key is in `homekube-main/ansible/roles/raspberry-pi/files/pub_keys/id_darth_homekube.pub`
- [ ] Run `01-update-control-node.yml` — configures darth (SSH config, /etc/hosts, tooling)
- [ ] Run `02-prepare-pis.yml` — creates `homekube` user, configures base OS
- [ ] Verify `ssh homekube@pi0` (and pi1–pi3) works from darth over Tailscale

---

## Phase 4 — Kubernetes Install

- [ ] Spec: OOM / swap strategy — write spec before implementing
- [ ] Run `03-setup-k8s-nodes.yml` — configures all nodes (cgroups, kernel, containerd, k8s packages)
- [ ] Run `04-setup-k8s-control-plane.yml` — kubeadm init on pi0
- [ ] Join worker nodes (pi1, pi2, pi3)
- [ ] Run `05-setup-cni.yml` — install Cilium
- [ ] Verify cluster health: all nodes Ready, system pods running

---

## Phase 5 — GitOps & Apps

- [ ] Run `06-setup-gitops.yml` — install ArgoCD
- [ ] Verify ArgoCD is up and syncing homekube-apps
- [ ] Verify all apps healthy: MetalLB, metrics-server, Longhorn, Prometheus, Grafana, Loki

---

## Documentation (update each phase as it's completed)

- [x] Restructure `homekube-main/docs/` — new file naming scheme, remove stale content
- [x] `01_bootstrap.md` — Imager + Tailscale + nmcli process
- [x] `02_nvme.md` — rsync-based NVMe clone
- [ ] `03_ansible.md` — fill in after Phase 3
- [ ] `04_kubernetes.md` — fill in after Phase 4
- [ ] `05_gitops.md` — fill in after Phase 5

---

## Backlog

- [ ] Investigate OOM root cause from previous run (kernel logs, events)
- [ ] Review all component versions against latest releases
- [ ] Set up Claude SSH autonomy (trust policy update)
- [ ] Clean up stale links in `homekube-main/README.md` (Setup section points to non-existent files: `01_conf_logs.md`, `02_01_node-configuration.md`, `02_02_kube_installation.md`, `02_03_argo_rollout.md` — replace with current `docs/01_bootstrap.md` … `05_gitops.md` once those phases are complete)
- [ ] Fix `enable_pciex.yml`: `file: state: touch` always reports changed; should be `state: file` (existence check) or removed (blockinfile will surface missing-file errors clearly)
