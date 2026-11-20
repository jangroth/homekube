# Longhorn runs on the workers with three replicas

Longhorn runs only on pi1–pi3: pi0 is the single control plane and its etcd shares the NVMe that replicas would use. Default replica count is 3, one per worker, because pi0 and pi2 have failed together and two replicas would take a volume offline. This costs about 50% more disk per volume than two replicas.

Replaces [Decisions 034](../archive/decisions/DECISIONS-2026-Q2.md) and [077](../archive/decisions/DECISIONS.md).
