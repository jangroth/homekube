# Drift is checked by hand from IaC; kernel reboots are deliberate

`task verify-drift` compares runtime with the versions in source and fails on drift. It runs manually from darth: CI has no network or SSH path into the cluster, because that would put a root-capable credential in a public repo's secrets for a check that is one local command. Updates report a pending kernel; rebooting into it is its own run (`task 23-rolling-reboot`, see ADR-0016).

Replaces [Decisions 066, 069](../archive/decisions/DECISIONS.md).
