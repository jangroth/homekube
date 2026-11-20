# Cilium LB-IPAM and L2 announcements expose LoadBalancer services

LoadBalancer VIPs come from a `CiliumLoadBalancerIPPool` on the home Wi-Fi subnet (192.168.86.241–251), announced on `wlan0` from pi1–pi3, so home devices reach them without routes. Cilium's `devices` include `tailscale0`, so VIP traffic arriving from darth over the Tailscale subnet route is DNAT'd on pi0.

## Considered Options

- **MetalLB**: dropped. With `wlan0` in Cilium's devices, Cilium probed MetalLB's VIPs as kernel neighbours and broke.
- **Pool on the switch subnet**: faster, but needs static routes or Tailscale routing for every home device.

Replaces [Decisions 019, 030, 031, 032](../archive/decisions/DECISIONS-2026-Q2.md).
