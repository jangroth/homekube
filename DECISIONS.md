# Decision Log

---

## 026 — README.md for human docs, CLAUDE.md for AI context only (2026-05-27)

**Decision:** Each repo has a `README.md` for human-readable operational documentation (what's deployed, how to access it, how to add an app). `CLAUDE.md` files are AI workspace context only — not the place for human-facing reference material.

**Rationale:** `CLAUDE.md` is loaded automatically by Claude Code and is written for an AI audience (concise, structured for tool consumption). A human landing on the repo from GitHub should find a `README.md` that explains what's running and how to operate it. The two documents serve different readers and should be maintained separately. `homekube-apps/README.md` was rewritten this session to reflect only currently deployed components; it grows as the spec rolls out.

---

## 025 — Spec 005 version table pins Helm chart versions, not app versions (2026-05-25)

**Decision:** All entries in the spec 005 Pinned Versions table record the **Helm chart version** (the value used as `targetRevision` in ArgoCD Application manifests) alongside the app version. Earlier entries recorded app versions only, which caused ArgoCD manifest failures when the two diverged (e.g. sealed-secrets chart `2.18.6` ships app `0.37.0`; Dex chart `0.24.0` ships app `2.44.0`; Velero chart `12.0.1` ships app `1.18.0`).

**Rationale:** ArgoCD's `targetRevision` is the Helm chart version — specifying an app version that doesn't exist as a chart version causes an immediate "chart not found" error at sync time. For most components chart = app (cert-manager, MetalLB, Longhorn, kubelet-csr-approver), but for projects where chart and app are versioned independently this distinction is critical. Catching this in the spec prevents silent failures at deploy time.

---

## 024 — Dedicated /storage partition on every NVMe node (2026-05-25)

**Decision:** Each Pi's NVMe is partitioned as: 512 MiB vfat boot (`nvme0n1p1`) + 80 GiB ext4 root (`nvme0n1p2`) + ~851 GiB ext4 storage (`nvme0n1p3`, `LABEL=storage`, mounted at `/storage`). Longhorn's `defaultDataPath` points to `/storage`. The `copy_mmc_to_nvme.yml` playbook is updated to produce this layout automatically on future provisioning runs.

**Rationale:** A bare `/storage` directory on the root filesystem (the original plan) gives Longhorn access to the entire 931 GiB NVMe but without isolation — a full storage volume could exhaust the root filesystem and destabilise the OS. A dedicated partition removes that risk and makes disk usage for storage independently observable. Repartitioning required booting from SD card because the root partition occupied the full NVMe (the SD-to-NVMe clone had already expanded). Now automated in `copy_mmc_to_nvme.yml`: the `expected` state classifier checks for 3 partitions with `LABEL=storage` on p3; the wipe+partition block creates the correct layout; the fstab entry is added to the clone before reboot.

---

## 023 — SD-first EEPROM boot order (0xf61) on all nodes (2026-05-25)

**Decision:** All four Pis are configured with `BOOT_ORDER=0xf61` (SD card first, NVMe fallback). With no SD card inserted the Pi boots NVMe normally. Inserting a SD card and power-cycling boots into it for recovery. The `copy_mmc_to_nvme.yml` playbook sets `0xf61` after NVMe migration.

**Rationale:** The only remote access path is Tailscale over WiFi. If the NVMe-booted OS loses WiFi connectivity (router reset, changed password) there is no way to SSH in and change the boot order — a catch-22. SD-first breaks that dependency: recovery is always "insert SD card + power cycle", which requires only physical access, not a working network. NVMe-first (`0xf16`) was originally chosen after NVMe migration but reversed once the WiFi-lockout scenario was considered. Trade-off accepted: a stray SD card left in a slot would cause the Pi to boot SD instead of NVMe — operationally, SD cards are kept out of slots during normal operation and stored nearby for recovery.

---

## 022 — Drop Bitnami MinIO chart, use upstream minio/minio (2026-05-23)

**Decision:** Use the upstream `minio/minio` Helm chart with the `quay.io/minio/minio:RELEASE.2025-10-15T17-29-55Z` image. Earlier spec drafts referenced `bitnami/minio` — removed.

**Rationale:** Broadcom restructured the Bitnami catalog in August 2025, moving most "free" images to the paid `bitnamisecure` registry. The free `bitnami/minio` chart is no longer reliable on fresh installs and has no upstream commitment to fix. The MinIO project's own chart is multi-arch (arm64 included), unaffected by Bitnami licensing, and tracks the latest MinIO release line directly. Same caution extends to any future Bitnami chart — verify the image is still pullable before adopting.

---

## 021 — Promtail → Grafana Alloy for log shipping (2026-05-23)

**Decision:** Use Grafana Alloy as the DaemonSet log shipper into Loki. Do not deploy Promtail.

**Rationale:** Grafana moved Promtail into feature-frozen maintenance in 2024 and named Alloy as its successor. Deploying Promtail on a fresh cluster builds in a forced migration within the lifetime of Phase 5. Alloy is the actively maintained path and configuration-wise is close enough to Promtail that the migration cost is paid once, now, instead of twice (now + later).

---

## 020 — sealed-secrets for in-git credentials (2026-05-23)

**Decision:** Use `bitnami-labs/sealed-secrets` (controller in `kube-system`, `kubeseal` CLI on darth) as the only mechanism for committing Kubernetes Secrets to git. No plaintext secrets in any repo. external-secrets + AWS Secrets Manager and SOPS+age were considered and rejected.

**Rationale:** Solo home-lab with a small number of secrets (MinIO root, Telegram bot, Google OAuth, AWS S3 creds) — a controller that round-trips sealed YAML in git is the simplest workflow with no external dependency. external-secrets adds an external store plus controller pods; SOPS+age requires ArgoCD plugin configuration that is fragile to maintain. The `bitnami-labs/sealed-secrets` project is the upstream maintainer repo and is unaffected by the Bitnami catalog changes (DECISION-022). Trade-off accepted: if the controller's signing key is lost without backup, every committed secret becomes unrecoverable; mitigation is exporting `kubeseal --fetch-cert` and the private key to the password manager immediately after first install.

---

## 019 — MetalLB L2 pool on home Wi-Fi subnet, not the wired cluster plane (2026-05-23)

**Decision:** The MetalLB `IPAddressPool` lives on `192.168.86.241–251` (home Wi-Fi `192.168.86.0/24`), not on the wired switch subnet `10.0.0.0/24` that carries inter-node and etcd traffic. ARP responses egress on `wlan0`. `L2Advertisement` is pinned to a subset of nodes (pi1/pi2/pi3) to keep failover deterministic and avoid GARP storms.

**Rationale:** LoadBalancer IPs need to be reachable from family devices on the home Wi-Fi without static routes or Tailscale subnet routing. Putting the pool on the wired `10.0.0.0/24` plane would have given a faster path but would have required either Tailscale subnet routing on pi0 (deferred) or static routes on every consuming device. Trade-off accepted: user-facing LB traffic crosses Wi-Fi, while cluster-internal traffic (etcd, inter-node) stays on the wired switch. Documented in the spec so it doesn't read as a misconfig in a future review.

---

## 018 — Accept single control plane on pi0, mitigate with etcd snapshots from wave -1 (2026-05-23)

**Decision:** Phase 5 does not introduce stacked-etcd HA. pi0 remains the sole control plane. Disaster recovery relies on an etcd snapshot systemd timer running on pi0 from the earliest wave, uploading to external S3 daily with 14-day retention. Restore procedure is manual and documented in `homekube-main/docs/restore-etcd.md`.

**Rationale:** Promoting pi1 and pi2 to control plane for a 3-node etcd quorum would have required nontrivial Ansible work (kubeadm join `--control-plane`, certificate distribution, re-templating workloads to tolerate fewer worker resources). For a home lab the cost is asymmetric — the realistic failure mode is NVMe/SD corruption on pi0, which a tested backup handles. Important: the etcd backup lives in wave `-1`, not wave `3` as the original spec draft had it. Backup must exist before any stateful workload runs, otherwise the first Longhorn-backed PVC is on borrowed time. Stacked-etcd HA is listed in the Deferred section for a future phase.

---

## 017 — Track latest upstream GA for every cluster component (Version Policy) (2026-05-23)

**Decision:** All Helm charts, application images, and Kubernetes components in `homekube-apps` track the latest upstream GA release. No release candidates, betas, alphas, or `*-pre.*` builds enter any wave. Patch and minor bumps applied on the cadence Renovate (or equivalent) surfaces them; major bumps reviewed for breaking values-schema changes, then applied promptly. The Pinned Versions table in `docs/specs/005-production-cluster-setup.md` is the source of truth at any given time and is re-verified at the start of each implementation session.

**Rationale:** Home cluster is a learning environment — accumulating tech debt from N-2 versions defeats the purpose, and the "let's not bump that until we have to" pattern silently builds upgrade cliffs. Renovate-style PRs into `homekube-apps` are cheap; merging them through ArgoCD is the same flow as any other change. Trade-off accepted: occasional values-schema breaks on major chart bumps (e.g. Loki chart `6.x → 7.x`) are absorbed up-front during the upgrade PR rather than amortised by drifting further behind.

---

## 016 — kubernetes Python package required for kubernetes.core on control node (2026-05-20)

**Decision:** Add `kubernetes>=31.0.0` to `homekube-main/pyproject.toml`. Convert all remaining raw shell commands in the `gitops` role (`kubectl get nodes`, `helm upgrade --install`) to `kubernetes.core` modules (`k8s_info`, `helm`), consistent with the rest of the role.

**Rationale:** `kubernetes.core` Ansible modules delegate to localhost (darth) and call the Kubernetes Python client directly — they do not shell out to `kubectl`. Without the `kubernetes` package in the venv, every `kubernetes.core.*` module fails with "Failed to import the required Python library (kubernetes)". Adding it to `pyproject.toml` keeps the dependency explicit and reproducible via `uv sync`. The shell-command inconsistency in the role (`helm upgrade --install` alongside `kubernetes.core.helm_*` tasks) was a leftover from an earlier draft; keeping all tasks as structured module calls means consistent return values and idiomatic Ansible (see DECISION-015 for the broader rationale).

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
