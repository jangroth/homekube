# Tailscale is the management plane; the switch is the cluster network

darth reaches the pis over Tailscale for SSH, ansible and kubectl, so the cluster is manageable from any network at addresses that survive DHCP. Kubernetes and etcd use only the physical switch (10.0.0.x): Tailscale stays invisible to the cluster and clear of the CNI.

Replaces [Decision 006](../archive/decisions/DECISIONS-2026-Q2.md).
