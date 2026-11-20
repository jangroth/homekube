# Single control plane on pi0, backed by etcd snapshots

pi0 is the only control plane. A daily etcd snapshot to S3 runs from wave -1, before any stateful workload, and restore is manual (`homekube-main/docs/restore-etcd.md`). Stacked-etcd HA would cost Ansible work and worker capacity against a failure (pi0 disk loss) that a tested backup already covers.

Replaces [Decision 018](../archive/decisions/DECISIONS-2026-Q2.md).
