# Decision Log

---

## 015 — kubernetes.core collection must be >=6.4.0 for Helm 4 compatibility (2026-05-20)

**Decision:** Pin `kubernetes.core` to `>=6.4.0` in `ansible/requirements.yml`. Upgrade any existing install before running Helm-related playbooks (`40-cni.yml`, `50-gitops.yml`).

**Rationale:** `kubernetes.core` 6.3.0 hard-codes a version guard requiring Helm `>=3.0.0,<4.0.0`. Helm 4.2.0 (current Homebrew install on darth) is rejected at the `helm_repository` task with "Helm version must be >=3.0.0,<4.0.0". Version 6.4.0 explicitly added full Helm 4 compatibility across all helm modules. Replacing the modules with raw `helm` shell calls was considered but rejected — the structured return values from the modules (status, chart, revision) are more useful than parsing stdout, and keeping idiomatic Ansible is preferable.

---

## 014 — configure_cgroups.yml must reboot after modifying cmdline.txt (2026-05-19)

**Decision:** Add a conditional `ansible.builtin.reboot` task to `configure_cgroups.yml` that fires only when the `lineinfile` task reports `changed`.

**Rationale:** The Pi 5 bootloader (EEPROM-based) prepends its own parameters — including `cgroup_disable=memory` — to the content of `/boot/firmware/cmdline.txt` before passing the full string to the kernel. Ansible's `lineinfile` appends `cgroup_enable=memory cgroup_memory=1` to cmdline.txt, but without a reboot these params never reach `/proc/cmdline`. The active cmdline therefore contains `cgroup_disable=memory` with no override, so `cgroup.controllers` at runtime omits `memory` and `kubeadm join` fails with `[ERROR SystemVerification]: missing required cgroups: memory`. The fix must live in `configure_cgroups.yml` (not in the 22 playbook) so it applies on any future run that actually changes the file.

---

## 013 — Pod DNS via public resolvers, not Tailscale (2026-05-19)

**Decision:** Deploy `/etc/kubernetes/resolv.conf` on all nodes (via `k8s-node` role) containing `1.1.1.1` and `8.8.8.8`. Reference this path in `kubeadm-config.yaml` and `join-config.yaml.j2` as `resolvConf`.

**Rationale:** The original config pointed to `/run/systemd/resolve/resolv.conf` (non-existent; systemd-resolved is inactive on Raspberry Pi OS) — this caused all control plane static pod sandboxes to fail at creation, blocking kubeadm init entirely. The fallback `/etc/resolv.conf` is managed by Tailscale and resolves via `100.100.100.100`, which is only reachable via the Tailscale virtual interface — not from pod network namespaces that route through eth0. Public DNS (1.1.1.1/8.8.8.8) is reachable via the physical switch → home router → internet, which is the correct data path for pods.

---

## 012 — cgroup regex must tolerate extra cmdline.txt tokens (2026-05-19)

**Decision:** Replace the fixed-pattern regex in `configure_cgroups.yml` with `^(console=serial0(?!.*cgroup_enable=memory).*)$` so the `lineinfile` task matches any line starting with `console=serial0` that doesn't already have the cgroup params.

**Rationale:** The original regex hard-coded the exact expected cmdline.txt content and failed silently (backrefs + no-match = no-op) when Pi Imager injected `ds=nocloud;i=rpi-imager-<timestamp>` between `rootwait` and `cfg80211.ieee80211_regdom=AU`. The memory cgroup was therefore never enabled, causing kubeadm preflight to fail with `missing required cgroups: memory`.

---

## 011 — kubeadm-config.yaml is the single source of truth for kubelet config (2026-05-17)

**Decision:** All kubelet configuration on the cluster originates from `roles/k8s-control-plane/files/kubeadm-config.yaml` (control plane) and `roles/k8s-worker/templates/join-config.yaml.j2` (workers). Re-running the Phase 4 playbooks re-renders `/var/lib/kubelet/config.yaml` on each node. Operators must **not** hand-edit `/var/lib/kubelet/config.yaml` — drift will be silently overwritten on the next playbook run, and reasoning about node behaviour becomes impossible if the live config diverges from the templates.

**Rationale:** Phase 3 deliberately deferred kubelet swap config (`failSwapOn`, `memorySwap.swapBehavior`) to Phase 4 (DECISION-009) precisely to avoid two competing sources. Spreading kubelet config across Phase 3 (kubelet package config) and Phase 4 (kubeadm) re-introduces the problem. Keeping the `KubeletConfiguration` block inside the kubeadm configs makes init/join the single point of authorship; kubeadm fills in unspecified defaults (`clusterDNS`, `clusterDomain`, `staticPodPath`, auth) automatically, so the file only needs to carry the deliberate overrides (cgroupDriver, swap).

---

## 010 — ansible managed by uv, not Homebrew (2026-05-16)

**Decision:** Remove the `Update ansible` task from `control-node/tasks/install_packages.yml`. Ansible is managed via `uv` in `homekube-main/pyproject.toml` (pinned `ansible-core>=2.18`); the Homebrew-installed `ansible` package is a separate, unversioned install that is never actually invoked (`uv run ansible-playbook` uses the venv).

**Rationale:** Two ansible installs with different version governance creates confusion. The Homebrew one is not what gets called — `uv run` uses `.venv/bin/ansible-playbook`. Homebrew's `state: latest` would silently update ansible outside the pinned version constraint.

---

## 009 — Enable and configure swap on pis, not disable it (2026-05-16)

**Decision:** Configure a 4 GiB swapfile (`/var/swap.img`) on each pi instead of disabling swap. Remove `dphys-swapfile`; create a fixed swapfile via `fallocate`; persist in `/etc/fstab`. Kubelet swap config (`failSwapOn: false`, `memorySwap.swapBehavior: LimitedSwap`) is deferred to Phase 4 via `kubeadm-config.yaml`.

**Rationale:** Kubernetes supports swap on Linux (NodeSwap feature, GA in 1.30+). OOM was observed on pi0 (control plane) during `kubeadm init` when image pulls exhausted 8 GB RAM. With 1 TB NVMe available, swap is cheap insurance. Disabling it entirely (`disable_swap.yml`) was the old k8s guidance, now superseded. Phase 3 deliberately leaves `failSwapOn` at its default (true) and passes `--ignore-preflight-errors=Swap` to the dry-run; the kubelet config is a Phase 4 deliverable so it has a single source of truth.

---

## 008 — Pi5 NVMe boot: MBR partition table + BOOT_ORDER=0xf16 (2026-05-15)

**Decision:** Partition the NVMe with MBR (msdos) label, not GPT. Set bootloader `BOOT_ORDER=0xf16` for NVMe-first SD-fallback.

**Rationale:** Empirical findings during automation of `copy_mmc_to_nvme.yml`:
- **MBR over GPT:** Pi5 firmware booted cleanly from MBR. GPT with the `esp` flag set on the boot partition did not boot — the firmware fell back to SD. MBR also matches the SD card's format, so PARTUUID handling stays consistent (msdos PARTUUIDs use the `-01`/`-02` suffix the playbook's regex targets).
- **`BOOT_ORDER=0xf16`, not 0xf61:** `BOOT_ORDER` is read right-to-left (rightmost digit = highest priority). `0xf16` means NVMe(6) first, SD(1) fallback, restart(f). The previous manual doc had `0xf61`, which is SD-first NVMe-second — pi0 was booting from SD with that value despite the doc claiming "NVMe first". Easy to "fix" backwards if not documented.

Both gotchas are now encoded in `ansible/roles/raspberry-pi/tasks/copy_mmc_to_nvme.yml` and the manual `docs/02_nvme.md` recipe.

---

## 007 — Bootstrap via Imager + manual nmcli, not prepare-sd.py (2026-05-14)

**Decision:** Flash SD cards using Raspberry Pi Imager with current WiFi credentials only. After first boot, add remaining networks (home, hotspot) manually via `nmcli con add`. Do not use `prepare-sd.py` to pre-bake WiFi into cloud-init.

**Rationale:** `prepare-sd.py` modifying cloud-init `user-data` proved unreliable in practice — PyYAML folded NM keyfile content (newlines → spaces), corrupting the keyfile; and the script was accidentally run against a live mounted card mid-session, switching the pi to a different WiFi and dropping the SSH session. Imager is battle-tested for initial WiFi. Manual `nmcli` commands after boot are explicit and auditable.

---

## 006 — Tailscale as management plane (2026-05-14)

**Decision:** Install Tailscale on each pi early in the bootstrap process (before NVMe clone, while still on SD). Use Tailscale (100.x.x.x) for all management access from darth — SSH, ansible, kubectl. k8s uses the physical switch (10.0.0.x) exclusively; Tailscale is invisible to k8s.

**Rationale:** Location independence — cluster is manageable from any network without home network credentials or static external IPs. Prompted by inability to reach pis from public WiFi. Tailscale provides stable addresses regardless of DHCP. Separating management plane (Tailscale) from data plane (physical switch) keeps k8s networking clean and avoids CNI conflicts.

---

## 005 — NVMe clone via rsync, not rpi-clone or dd (2026-04-22)

**Decision:** Clone SD → NVMe using `mkfs` + `rsync -axH` + PARTUUID substitution. Do not use `dd` or `rpi-clone`.

**Rationale:** `dd` causes PARTUUID collision when both SD and NVMe are present — the bootloader can't distinguish them, causing boot failures. `rpi-clone` doesn't support NVMe naming conventions (`nvme0n1p1` vs `nvme0n11`) and aborts. The rsync approach creates fresh PARTUUIDs on the NVMe and explicitly updates `/etc/fstab` and `cmdline.txt` to match.

---

## 004 — ansible-core over full ansible bundle (2026-04-20)

**Decision:** Use `ansible-core` (not the full `ansible` package) with explicit collection management via `ansible/requirements.yml`.

**Rationale:** Leaner install, forces explicit declaration of what collections are actually used, easier to pin precisely. Collections required: `ansible.posix`, `community.crypto`, `community.general`, `kubernetes.core`.

---

## 003 — Nuke and reprovision (2026-04-19)

**Decision:** Reprovision all 4 pis from scratch (fresh SD card flash) rather than attempting to diagnose and repair the existing cluster state.

**Rationale:** Cluster state is unknown after months dormant. Suspected OOM crash. Clean start is more reliable and gives a known baseline.

---

## 002 — Spec-driven AI development (2026-04-19)

**Decision:** Follow spec-driven development for all significant work. Before implementation, write a spec in `docs/specs/NNN-title.md` defining: problem, acceptance criteria, out-of-scope, and approach.

**Rationale:** Keeps the human in the driver's seat on *what* gets built. Specs are learning artifacts. Prevents AI from going off in unexpected directions. Aligns with the goal of learning AI-driven development.

---

## 001 — Workspace structure (2026-04-19)

**Decision:** Use a thin parent git repo at `/Users/jan/Projects/kube/homekube/` to track shared AI context, todo, and decisions. Child repos (`homekube-main`, `homekube-apps`) remain independent git repos — not submodules.

**Rationale:** Keeps shared documentation versioned without submodule complexity. Parent `CLAUDE.md` is automatically loaded by Claude Code when working in any child directory. Three separate GitHub repos.

**Repos:** `jangroth/homekube` (workspace), `jangroth/homekube-main`, `jangroth/homekube-apps`
