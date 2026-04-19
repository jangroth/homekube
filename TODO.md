# TODO

## In Progress

- [ ] AI workspace setup (CLAUDE.md, TODO, DECISIONS, repo structure)

---

## Phase 1 — Hardware Prep

- [ ] Flash fresh Raspberry Pi OS Lite 64-bit to SD cards for all 4 pis
  - Configure initial user: `boot` / `boot` (required for ansible bootstrap)
  - Configure hostname (pi0–pi3) and enable SSH via Raspberry Pi Imager
- [ ] Verify pis boot from SD card and are reachable on the network
- [ ] Physical NVMe step: follow vendor instructions per pi (one-time per device)
  - pi0, pi1, pi2, pi3 — track individually

---

## Phase 2 — Bootstrap Provisioning (Ansible)

- [ ] Verify darth's SSH key is in `homekube-main/ansible/roles/raspberry-pi/files/pub_keys/id_darth_homekube.pub`
- [ ] Run `02-prepare-pis.yml` — creates `homekube` user, configures base OS
- [ ] Run `01-update-control-node.yml` — configures darth (SSH config, /etc/hosts, tooling)
- [ ] Verify `ssh homekube@pi0` (and pi1–pi3) works from darth

---

## Phase 3 — Kubernetes Install

- [ ] Spec: OOM / swap strategy — write spec before implementing
- [ ] Run `03-setup-k8s-nodes.yml` — configures all nodes (cgroups, kernel, containerd, k8s packages)
- [ ] Run `04-setup-k8s-control-plane.yml` — kubeadm init on pi0
- [ ] Join worker nodes (pi1, pi2, pi3)
- [ ] Run `05-setup-cni.yml` — install Cilium
- [ ] Verify cluster health: all nodes Ready, system pods running

---

## Phase 4 — GitOps & Apps

- [ ] Run `06-setup-gitops.yml` — install ArgoCD
- [ ] Verify ArgoCD is up and syncing homekube-apps
- [ ] Verify all apps healthy: MetalLB, metrics-server, Longhorn, Prometheus, Grafana, Loki

---

## Backlog

- [ ] Investigate OOM root cause from previous run (kernel logs, events)
- [ ] Improve NVMe boot documentation / automate where possible
- [ ] Review all component versions against latest releases
- [ ] Set up Claude SSH autonomy (trust policy update)
