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

### Changed
- `homekube-main` — `cilium_version` 1.20.2→1.20.1 in `ansible/group_vars/all.yml`, and Renovate updates for the `cilium` dep disabled (`enabled: false` packageRule in `renovate.json`). The version is now deliberately held, not tracked; see [decision 065](DECISIONS.md). Rolled out to the cluster via `task 40-cni` the same day, without incident — this clears the endpoint-creation block, so new pods can be scheduled on all four nodes again.

### Fixed
- Corrected the root-cause analysis of the 2026-10-02 Cilium 1.20.2 failure (below). Three findings overturn what was recorded then:
  - **The proposed `socketLB.enabled: false` fix is a no-op.** The live `cilium-config` configmap already had `bpf-lb-sock: "false"` (it is the chart default), and all four agents were still looping on `cil_sock6_connect`/`cil_sock6_post_bind` with that setting in force. Under `kubeProxyReplacement: true` the cgroup socket-LB programs load unconditionally and cannot be disabled from Helm values. [PR #23](https://github.com/jangroth/homekube-main/pull/23) and [issue #51](https://github.com/jangroth/homekube/issues/51) should be closed on this basis.
  - **Impact was blocker-level, not cosmetic.** The datapath orchestrator never completes on any node, so CNI ADD is starved (`[PUT /endpoint/{id}][429] putEndpointIdTooManyRequests`, ~1234 occurrences over 25h): no new pod can get an endpoint on any node. Existing pods survived on already-programmed rules, which is what made it look harmless; the agents also reported `1/1 Running`/`Ready=True`/`RESTARTS 0` throughout.
  - **Root cause is a Cilium regression, not a configuration mistake.** [cilium/cilium#47737](https://github.com/cilium/cilium/pull/47737) replaced a compile-time `#ifdef HAVE_SET_RETVAL` in `try_set_retval()` with the load-time CO-RE builtin `bpf_core_enum_value_exists()`, making kernel BTF a runtime requirement. Affected tags verified individually: 1.19.8 and 1.20.2 only; 1.18.x, 1.19.0–1.19.7 and 1.20.0–1.20.1 are unaffected. Upstream: [cilium/cilium#48778](https://github.com/cilium/cilium/issues/48778).
- Confirmed the 2026-10-02 claim that BTF is absent on RPi OS kernels, and that the staged 6.18.50 reboot would not have helped: no `/sys/kernel/btf/` on pi0–pi3, zero `DEBUG_INFO_BTF` in `bcm2712_defconfig`, no `.BTF` module section in either 6.18.39 or 6.18.50.

### Decisions
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

