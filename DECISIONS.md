# Decision Log

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
