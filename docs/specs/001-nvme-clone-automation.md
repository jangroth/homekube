# Spec 001 — NVMe Clone Automation

**Status:** Done
**Owner:** Jan
**Created:** 2026-05-15

---

## Problem

The validated NVMe clone process (`docs/02_nvme.md`) is currently manual — 10 shell steps per pi, run over SSH. With 4 pis to migrate to NVMe boot, this is repetitive and error-prone. The existing `ansible/roles/raspberry-pi/tasks/copy_mmc_to_nvme.yml` is stale: it uses the `dd`-based approach that DECISION-005 ruled out, and the entire file is commented out.

Goal: encode the validated rsync-based clone into ansible tasks that run idempotently over Tailscale, with safety guards strong enough that an accidental run on a wrong host or wrong state does not destroy data.

## Acceptance Criteria

1. `task nvme` (or equivalent ansible-playbook invocation) clones SD → NVMe on a fresh-but-PCIe-enabled pi and produces a pi that boots from NVMe after reboot + SD removal.
2. Re-running the playbook on a pi that **already boots from NVMe** detects the migrated state in preflight and **exits successfully without touching the disk** (no destructive action, no failed task — the play reports "already migrated, skipping" and ends the host).
3. Re-running after a partial failure (e.g. crash mid-rsync, or after partitions were created but before rsync completed) recovers without manual intervention, provided the on-disk state matches the **expected layout** (see Idempotency strategy). The rsync resumes; sed/boot-order steps are re-applied idempotently. If the on-disk state does **not** match the expected layout, the playbook fails loudly per AC #4 and the operator sets `nvme_force_wipe: true` to recover.
4. Playbook **fails loudly** (clear error, no destructive action) when any precondition is unmet:
   - `/dev/nvme0n1` does not exist (on the target host)
   - PCIe is not enabled in `/boot/firmware/config.txt` (both `dtparam=pciex1` and `dtparam=pciex1_gen=3`)
   - `/dev/nvme0n1` has partitions that do **not** match the expected layout, and `nvme_force_wipe: true` is not set
   - NVMe used-space target is smaller than the SD card's used space on `/`
5. Boot order change to `0xf61` (NVMe → SD fallback) is applied only after the clone is verified.
6. After playbook completes on all of pi0–pi2, the operator can: power off, remove SD, power on, and reach the pi over Tailscale with `findmnt /` showing `/dev/nvme0n1p2`.
7. `docs/02_nvme.md` is updated to reflect the automated flow (kept as reference for the underlying steps, but the operator-facing instructions point to ansible).

## Out of Scope

- pi3 onboarding (blocked on free SD card; tracked separately in `TODO.md`).
- Automating the physical NVMe attachment (human checkpoint per `CLAUDE.md`).
- Any change to the partition layout beyond what the manual process produces (boot + root only). The `/storage` partition is deferred until Longhorn setup (Phase 5) and will be specified there. **Note:** the existing `configure_nvme.yml` (which creates a p3 starting at 129GB, incompatible with this spec's layout where p2 spans `513MiB → 100%`) is not currently imported by `roles/raspberry-pi/tasks/main.yml`, so it remains dormant without further action. The Longhorn spec will rewrite it and add the import.
- EEPROM update itself — assume `rpi-eeprom-update -a` was already run during initial bootstrap (verify in `enable_pciex.yml` or fold in if missing; tracked as a preflight risk, not a goal of this spec).

## Approach

### Split into two playbooks around the human checkpoint

| Phase | Playbook | When | Notes |
|-------|----------|------|-------|
| Pre-attach | `enable_pciex.yml` (exists) | NVMe **not** attached yet | Existing role, runs idempotently. Followed by reboot + shutdown for physical attach. |
| Post-attach | `copy_mmc_to_nvme.yml` (rewrite) | NVMe attached, pi booted from SD | All steps 4–8 of `02_nvme.md`. Reboots at end. |

The human checkpoint (physical NVMe attach) sits between them. Operator runs phase 1, performs the physical step, then runs phase 2.

### Safety guards (run first in `copy_mmc_to_nvme.yml`)

A `preflight` block runs before any destructive action. It has two distinct outcomes:

- **Short-circuit success** (no failure, no destructive action, host marked done):
  - **Already migrated:** `findmnt -no SOURCE /` returns `/dev/nvme0n1p2`. Play ends the host with a clear "already migrated, skipping" message. Implements AC #2.

- **Hard fail** (assert, no destructive action):
  1. **NVMe present:** `stat /dev/nvme0n1` succeeds.
  2. **PCIe enabled:** both `dtparam=pciex1` and `dtparam=pciex1_gen=3` present in `/boot/firmware/config.txt`.
  3. **Disk used-space sanity:** used space on `/` (via `df`) fits comfortably in the planned NVMe root partition. Rsync would fail mid-clone otherwise — fail upfront.
  4. **NVMe state classifier** — inspect `/dev/nvme0n1` and decide:
     - *Blank* (no partition table): proceed to partition + format + rsync.
     - *Expected layout* (GPT, exactly two partitions: p1 vfat ~512MiB starting at 1MiB, p2 ext4 spanning to end of disk): treat as a resumable prior run — **skip wipe/partition/mkfs**, mount, proceed to rsync (which is idempotent). Implements AC #3 partial-failure recovery.
     - *Anything else* (different partition count, different fstypes, different sizes, foreign data): hard fail unless `nvme_force_wipe: true` is set. Implements AC #4.

### Idempotency strategy

- **Expected layout** (the precise definition referenced by guards above): GPT label, exactly two partitions on `/dev/nvme0n1`:
  - p1: vfat, start `1MiB`, end `513MiB` (±1MiB tolerance)
  - p2: ext4, start `513MiB`, end = disk end
  Any deviation → "anything else" branch of the state classifier.
- `wipefs` + `parted` + `mkfs`: only run on the *blank* branch. On the *expected layout* branch they are skipped; rsync proceeds over the existing filesystem.
- `rsync -axH --delete`: naturally idempotent (re-runs are fast).
- `sed` on cloned fstab/cmdline.txt: idempotent because the new NVMe PARTUUIDs do not contain the SD's `-01`/`-02` suffix the regex targets — a second run is a no-op. Guard with `grep` before `sed` to keep the task `changed_when` honest.
- Boot order: `rpi-eeprom-config` write only if current value ≠ `0xf61`.

### Verification before boot-order flip

Before the final `BOOT_ORDER=0xf61` write, the playbook must verify:
- `/mnt/clone/etc/fstab` references the new NVMe PARTUUIDs (not the old SD ones).
- `/mnt/clone/boot/firmware/cmdline.txt` has `root=PARTUUID=<nvme-root-partuuid>`.

If either check fails: do not flip boot order, fail loudly.

### Reboot handling

End of playbook reboots the pi. Use ansible's `reboot` module with a Tailscale-reachable post-reboot check (the pi is on the **SD card** still after first reboot; SD fallback in `0xf61` means it should still boot fine even if NVMe is somehow bad). Operator verifies, then physically removes SD per `02_nvme.md` Step 9.

## Resolved Decisions

1. **SD fallback verification (step 10) stays manual.** A one-line operator instruction in `docs/02_nvme.md` is sufficient. The playbook cannot drive the physical SD reinsertion that needs verifying, so adding ansible for the post-reinsertion check alone is overkill.
2. **`/storage` is for Longhorn and stays out of scope.** Deferred to the Longhorn setup spec (Phase 5). `configure_nvme.yml` is already not imported by `roles/raspberry-pi/tasks/main.yml`, so no action is needed here to keep it dormant.
3. **NVMe presence is detected at runtime, not via inventory host vars.** The preflight `stat /dev/nvme0n1` is the source of truth. Operator uses `--limit pi0,pi1,pi2` to avoid running against pi3 (no NVMe yet). The softer `meta: end_host` alternative is rejected: it would blur the difference between "host not migrated yet" and "NVMe dropped off PCIe bus mid-migration", which is a real failure mode worth surfacing.
4. **Serial execution (`serial: 1`).** First-time migration only — failure on pi0 stops the play before pi1/pi2 are touched. Parallel is rejected for now: time-saving is marginal on a 3-host one-shot migration, and serial keeps the stop-on-first-failure signal clean.

## Validation Plan

1. Run phase 1 (`enable_pciex.yml`) on pi0 — already done; verify task is no-op when re-run.
2. Physically attach NVMe to pi0.
3. Dry-run phase 2 on pi0 with `--check` first, then live.
4. Reboot, verify `findmnt /` → `/dev/nvme0n1p2`.
5. Re-run phase 2 on the migrated pi0 — must short-circuit cleanly via the "already migrated" preflight branch (acceptance criterion #2): play succeeds, no tasks beyond preflight execute.
6. Repeat for pi1, pi2.
7. Update `TODO.md` checkboxes in Phase 2.

## References

- Manual process: `docs/02_nvme.md`
- Decision on rsync vs dd: `DECISIONS.md` § 005
- Decision on Tailscale management plane: `DECISIONS.md` § 006
- Existing ansible role: `ansible/roles/raspberry-pi/tasks/`
