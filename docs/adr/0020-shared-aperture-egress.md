# Workspaces reach Aperture through one shared egress

Aperture is tailnet-only, so workspaces call `aperture-egress`, one in-cluster deployment of a tailscale container and a reverse proxy, as a ClusterIP Service. Tailnet credentials stay in that one namespace, out of every workspace. Aperture sees a single identity for all workspaces: quotas apply to them together, and per-task attribution comes from Hermes's logs.

## Considered Options

- **A tailnet node per workspace**: per-workspace identity in Aperture, but a tailnet auth key in every workspace.
- **Tailscale Kubernetes operator**: a new cluster-wide component for one use; Hermes already reaches Aperture through a sidecar without it.
