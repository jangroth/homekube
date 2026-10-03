# Changelog

All notable changes to the homekube project (`homekube/`, `homekube-main/`, `homekube-apps/`).

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Entries are reverse-chronological; each dated section groups changes by type:

- **Added** — new components, files, or capabilities
- **Changed** — modifications to existing config, versions, or behaviour
- **Removed** — deletions and decommissioning
- **Fixed** — bug fixes
- **Operational** — manual interventions, recoveries, one-off ops actions
- **Decisions** — links to `DECISIONS.md` entries created on this day

Cross-repo entries reference commits as `repo@sha` (e.g. `homekube-main@e77a322`). Where a change has an associated decision or spec, link it inline.

Current quarter only. Prior quarters: [2026 Q2](CHANGELOG-2026-Q2.md), [2026 Q3](CHANGELOG-2026-Q3.md).

---

## 2026-10-03

### Added
- `homekube-main` — drift verification in IaC: `ansible/90-verify-drift.yml` (`task verify-drift`), a read-only playbook comparing runtime against `ansible/group_vars/all.yml` (kernel, kube packages, containerd, etcdctl, watchdog, Cilium image) and checking the four nodes agree with each other, exiting non-zero on drift. Kernel staleness comes from a reusable `roles/k8s-node/tasks/check_pending_reboot.yml` that reads `dpkg-query -W -f='${Depends}' linux-image-rpi-2712`, because `/var/run/reboot-required` is never written on RPi OS Lite (no `update-notifier-common`). See [decision 066](DECISIONS.md).
  - First run found **every node running a stale kernel**: pi0/pi2 on 6.18.39, pi1/pi3 on 6.18.29, with 6.18.50 installed on all four. Nothing else drifted — `group_vars/all.yml` matches runtime on every pin, and kube packages (1.37.0-1.1), containerd 2.4.1, etcdctl 3.7.2, Tailscale 1.102.4 and `RuntimeWatchdogUSec=10min` are uniform across pi0–pi3. Rebooting into 6.18.50 does not unlock Cilium 1.20.2 (no BTF in any 6.18.x RPi kernel, decision 065) — it is hygiene, not an escape route.
- `homekube-main` — `ansible/23-rolling-reboot.yml` (`task 23-rolling-reboot`) plus `roles/k8s-node/tasks/reboot_node.yml`: reboots nodes into their installed kernel one at a time, pi1→pi2→pi3→pi0, by cordoning rather than draining. Longhorn's three `instance-manager-*` PDBs allow **0** disruptions, so `kubectl drain` deadlocks and times out — see [decision 067](DECISIONS.md), which also covers the single-replica window this accepts. Per node it gates on Longhorn being healthy, verifies the booted kernel, and blocks on replica rebuild before advancing. Runs as a preview and changes nothing unless given `-e confirm_reboot=yes`; verified in preview against all four nodes (`changed=0`). **Not yet executed** — the kernel drift above is still open.

### Changed
- `homekube-main` — `cilium_version` 1.20.2→1.20.1 in `ansible/group_vars/all.yml`, and Renovate updates for the `cilium` dep disabled (`enabled: false` packageRule in `renovate.json`). The version is now deliberately held, not tracked; see [decision 065](DECISIONS.md). Rolled out to the cluster via `task 40-cni` the same day, without incident — this clears the endpoint-creation block, so new pods can be scheduled on all four nodes again.
- `homekube-main` — `roles/k8s-node/tasks/update_system.yml` now reports a pending kernel reboot after its apt tasks (report-only). In `roles/raspberry-pi/tasks/update_system.yml` the dead `/var/run/reboot-required` stat was replaced with the same check and the `reboot:` task gated behind `-e allow_reboot=true` — that task had never once fired, so making the check work would otherwise have started rebooting nodes during provisioning.
- `CLAUDE.md` — versions removed from the Stack table, which now points at `homekube-main/ansible/group_vars/all.yml` and `homekube-apps/applications/**/*.yaml` → `targetRevision`. All three versions it carried (Kubernetes v1.36.1, Cilium 1.19.4, Longhorn 1.11) were simultaneously stale against runtime (v1.37.0, 1.20.1, 1.12.1); since [decision 064](DECISIONS-2026-Q3.md) gave Renovate ownership of those pins, a hand-maintained copy can only be correct between bumps. The Cilium hold stays in the table as a constraint.
- `homekube-main` — `docs/ref_operations.md` watchdog section gained a `status` block recording the standing state while #22 is open: the four occurrences through 2026-08-22 were vendor-1min load stalls, the 2026-09-13 double outage is unattributed, and no reset has occurred since 2026-09-14 across two Helm rollouts. Verified against boot history on all four nodes (pi0 up since 2026-09-14 17:03, pi2 2026-09-13 14:52, pi1 2026-06-16, pi3 2026-05-27) and `RuntimeWatchdogUSec=10min` live on each, matching `roles/k8s-node/files/50-homekube-watchdog.conf`.

### Operational
- **All four nodes rebooted into kernel 6.18.50**, closing the drift found this morning — pi1 16:08, pi2 16:16, pi3 16:57 via `task 23-rolling-reboot`; pi0 16:28 as a side effect of the outage below. `task verify-drift` now reports "Runtime matches declared state on all nodes" (it failed on all four at the start of the day).
- **Unplanned two-node outage mid-rollout.** pi0 stopped logging at 16:17:04 and pi2 at 16:17:41 — 37s apart, pi2 only 75s after its planned reboot. Both needed manual power-cycles. Root-caused to power starvation, not the watchdog — see [decision 068](DECISIONS.md). pi1 recorded `Undervoltage detected!` at 16:18:08 and survived, which is the evidence that settles it. No data lost; the rolling-reboot play's Longhorn pre-flight correctly refused to continue onto pi3 while the cluster was degraded, on both halted runs.
- Longhorn `numberOfReplicas` raised 2→3 on all three volumes before rebooting pi3, so redundancy stayed at two running replicas throughout. Recommended to keep at 3: with three data-plane nodes that is one copy per node, costs ~58Gi against 1TB NVMe each, and the nodes demonstrably die unpredictably.

### Removed
- Closed [PR #20](https://github.com/jangroth/homekube-main/pull/20) (watchdog investigation conclusion) unmerged. It was opened 2026-09-15, ~40h after #22 was reopened for an unmet exit criterion, and asserted the 10min watchdog fix proven; it also carried a `Closes #22` reference that would have auto-closed the issue a second time (PR #16 already did once). Its root-cause line omitted the 2026-09-13 pi0+pi2 double outage, which [decision 061](DECISIONS-2026-Q3.md) leaves unattributed. [Issue #22](https://github.com/jangroth/homekube/issues/22) stays open.
- Closed [issue #43](https://github.com/jangroth/homekube/issues/43) (high pod restart counts) as not reproducing, and [PR #21](https://github.com/jangroth/homekube-main/pull/21) (pod restart triage runbook) unmerged. The 212/84/49 counts recorded on 2026-09-12 belonged to the pod cohort that predated Cilium ControllerRevision 9 (oldest revision 2026-05-20), accumulated over ~4 months on nodes with uptimes back to May. That revision — `855858b5d4`, Cilium 1.20.1, the same template running again after the rollback above — ran 2026-09-12→10-01 with 3 cilium-agent and 5 cilium-operator restarts total, and `increase(kube_pod_container_status_restarts_total[14d])` is 0 cluster-wide. Prometheus retention (15d) cannot reach 2026-09-12, so the original cause is unrecoverable; `KubePodCrashLooping` and `KubeContainerWaiting` cover regression. The PR's content was generic kubectl triage rather than cluster-specific reference material.

### Fixed
- Corrected the root-cause analysis of the 2026-10-02 Cilium 1.20.2 failure (below). Three findings overturn what was recorded then:
  - **The proposed `socketLB.enabled: false` fix is a no-op.** The live `cilium-config` configmap already had `bpf-lb-sock: "false"` (it is the chart default), and all four agents were still looping on `cil_sock6_connect`/`cil_sock6_post_bind` with that setting in force. Under `kubeProxyReplacement: true` the cgroup socket-LB programs load unconditionally and cannot be disabled from Helm values. [PR #23](https://github.com/jangroth/homekube-main/pull/23) and [issue #51](https://github.com/jangroth/homekube/issues/51) should be closed on this basis.
  - **Impact was blocker-level, not cosmetic.** The datapath orchestrator never completes on any node, so CNI ADD is starved (`[PUT /endpoint/{id}][429] putEndpointIdTooManyRequests`, ~1234 occurrences over 25h): no new pod can get an endpoint on any node. Existing pods survived on already-programmed rules, which is what made it look harmless; the agents also reported `1/1 Running`/`Ready=True`/`RESTARTS 0` throughout.
  - **Root cause is a Cilium regression, not a configuration mistake.** [cilium/cilium#47737](https://github.com/cilium/cilium/pull/47737) replaced a compile-time `#ifdef HAVE_SET_RETVAL` in `try_set_retval()` with the load-time CO-RE builtin `bpf_core_enum_value_exists()`, making kernel BTF a runtime requirement. Affected tags verified individually: 1.19.8 and 1.20.2 only; 1.18.x, 1.19.0–1.19.7 and 1.20.0–1.20.1 are unaffected. Upstream: [cilium/cilium#48778](https://github.com/cilium/cilium/issues/48778).
- Confirmed the 2026-10-02 claim that BTF is absent on RPi OS kernels, and that the staged 6.18.50 reboot would not have helped: no `/sys/kernel/btf/` on pi0–pi3, zero `DEBUG_INFO_BTF` in `bcm2712_defconfig`, no `.BTF` module section in either 6.18.39 or 6.18.50.

### Decisions
- [068 — The node crashes are power starvation, not the watchdog; supersedes the premise of 054](DECISIONS.md)
- [067 — Reboot Longhorn nodes by cordon-and-rebuild, not drain](DECISIONS.md)
- [066 — Drift detection belongs in IaC; kernel reboots are deliberate, never a side effect](DECISIONS.md)
- [065 — Hold Cilium at 1.20.1; kernel BTF is becoming a hard Cilium requirement that Raspberry Pi OS does not satisfy](DECISIONS.md)

---

## 2026-10-02

### Changed
- `homekube-main@1550472` (PR #22): Renovate-proposed Ansible-pinned version bumps — `argocd_helm_chart_version` 10.9.0→10.9.2, `cilium_version` 1.20.1→1.20.2, `containerd_version` 2.3.5→2.4.1, `etcdctl_version` 3.7.1→3.7.2. Merged and rolled out live to all 4 nodes (`task 50-gitops`, `task 40-cni`, `task 22-k8s-nodes`); pi0's containerd restart (static-pod-impacting) completed cleanly.
- `homekube-main@405bf76`: added `update_repo_cache: true` to the `gitops` role's ArgoCD Helm install/upgrade task, matching the `cni` role's existing Cilium task — without it, a stale local Helm index on darth can reject a chart version released after the last `helm repo update`, as happened on this rollout's first `task 50-gitops` attempt.

### Operational
- `task 40-cni`'s Cilium 1.20.2 upgrade applied cleanly to all 4 agents/operator, but the Helm release itself is stuck `failed` (revision 7): `hubble-relay`/`hubble-ui` can't get a CNI endpoint on pi3 — the Cilium agent's `cil_sock4/6_*` eBPF programs (required by `kubeProxyReplacement: true`'s socket-level LB) fail to load with "no BTF found for kernel version 6.18.29+rpt-rpi-2712: not supported". Confirmed cluster-wide (pi0/pi1/pi3 all lack `/sys/kernel/btf/vmlinux`). Restarting the agent doesn't help — re-enters the same loop and additionally forces all of that node's existing endpoints into `restoring`/`regenerating` (no actual workload impact observed: ArgoCD/Longhorn pods on pi3 stayed `Running`/`Healthy` throughout via already-programmed datapath rules). Root cause and proposed fix (`socketLB.enabled: false`) filed as [issue #51](https://github.com/jangroth/homekube/issues/51). **Superseded 2026-10-03** — the proposed fix is a no-op, the impact was blocker-level rather than workload-neutral, and the root cause is an upstream Cilium regression; see the 2026-10-03 entry and [decision 065](DECISIONS.md).

### Decisions
- None — the gitops role fix and the socketLB root-cause analysis didn't rise to a standalone decision; captured here and in issue #51 instead.

---

