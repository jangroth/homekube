# Pods resolve DNS through public resolvers

Kubelet's `resolvConf` is `/etc/kubernetes/resolv.conf` (1.1.1.1, 8.8.8.8), deployed by the `k8s-node` role. The node's `/etc/resolv.conf` belongs to Tailscale (100.100.100.100), which pod network namespaces cannot reach, and systemd-resolved is inactive on Raspberry Pi OS.

Replaces [Decision 013](../archive/decisions/DECISIONS-2026-Q2.md).
