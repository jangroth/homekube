# Recovery is Longhorn backups plus git; no Velero

Manifests come back from git through ArgoCD and volume data from Longhorn's S3 backups, so Velero adds no restore capability for its controller, snapshot CRDs and second S3 credential. Longhorn owns retention (`retain` on each RecurringJob) and the bucket has no object expiry: backups share blocks, and an age-based expiry would delete blocks newer backups still reference.

## Consequences

Objects applied outside git are lost on a rebuild.

Replaces [Decisions 071, 072](../archive/decisions/DECISIONS.md).
