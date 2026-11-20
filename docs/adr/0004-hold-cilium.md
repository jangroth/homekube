# Hold Cilium at 1.20.1

From 1.19.8 and 1.20.2 Cilium needs kernel BTF at load time (cilium/cilium#47737), and the Raspberry Pi OS kernel ships none: agents report Ready while no new pod gets an endpoint. `cilium_version` is pinned in `homekube-main/ansible/group_vars/all.yml` and Renovate is disabled for it. Revisit when Raspberry Pi OS ships BTF or Cilium drops the requirement (upstream: cilium/cilium#48778).

## Considered Options

- **`socketLB.enabled: false`**: rejected as a no-op; the failing programs still load.

Replaces [Decision 065](../archive/decisions/DECISIONS.md).
