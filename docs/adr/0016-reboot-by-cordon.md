# Reboot Longhorn nodes by cordon, not drain

`task 23-rolling-reboot` reboots one node at a time, data plane first, by cordoning: it checks every volume is healthy before and after each node. `kubectl drain` cannot finish here, because each Longhorn instance-manager carries a PDB allowing zero disruptions while it hosts a replica.

## Considered Options

- **Longhorn `node-drain-policy: block-for-eviction`**: rejected; it copies every replica off the node on each reboot.

Replaces [Decision 067](../archive/decisions/DECISIONS.md).
