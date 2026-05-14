# TODO

## Done

- [x] AI workspace setup (CLAUDE.md, TODO, DECISIONS, repo structure)
- [x] Pin Python (3.12) and ansible-core (2.20.4) via uv in homekube-main
- [x] NVMe clone approach validated manually on pi0 (rsync, not dd/rpi-clone — see DECISION-005)

---

## Phase 0 — Tailscale Prereqs (one-time)

- [ ] Generate reusable ephemeral auth key in Tailscale admin console
- [ ] Store auth key in ansible-vault

---

## Phase 1 — All Pis Bootstrap (pi0–pi3, same process)

For each pi:
- [ ] Flash fresh Raspberry Pi OS Lite 64-bit SD card (current WiFi credentials, `boot`/`boot` user)
- [ ] Boot from SD, verify internet connectivity
- [ ] Install Tailscale + join tailnet — verify darth can reach pi over Tailscale
- [ ] Physical NVMe attachment (Pimoroni base)

---

## Phase 2 — NVMe Automation (via Tailscale)

- [ ] Encode validated NVMe setup process into ansible (`copy_mmc_to_nvme.yml`)
  - Replace commented-out dd approach with rsync-based approach
  - Steps: wipefs, parted, mkfs, rsync, UUID fix, boot order
- [ ] Run ansible NVMe setup for all 4 pis over Tailscale
- [ ] Verify all 4 pis boot from NVMe and rejoin tailnet

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

## Backlog

- [ ] Investigate OOM root cause from previous run (kernel logs, events)
- [ ] Review all component versions against latest releases
- [ ] Set up Claude SSH autonomy (trust policy update)
