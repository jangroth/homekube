# Spec 009 — Infisical, phase 1: self-hosted install

**Status:** Draft (2026-11-01)
**Related decisions:** [Decision 079](../../DECISIONS.md) — Infisical adopted as the secret store, phased; amends [decision 020](../../DECISIONS-2026-Q2.md). [Decision 022](../../DECISIONS-2026-Q2.md) — caution on Bitnami images.
**Related issues:** [#69](https://github.com/jangroth/homekube/issues/69) — Hermes backup label not in source (uses the shared backup job introduced here).

---

## 1. Problem

Secrets reach the cluster through sealed-secrets (decision 020): roughly ten of them, sealed by hand on darth, with plaintext originals kept in the password manager. Every change means re-sealing, committing and waiting for ArgoCD. Nothing outside the cluster (Ansible, Terraform, scripts on darth) shares the store. The planned Coder + Hermes work adds many short-lived consumers that each need a scoped set of secrets, which hand-sealed YAML doesn't scale to.

Phase 1 installs Infisical and nothing else, so it can be explored before anything depends on it.

## 2. Phases

| Phase | Scope | Spec |
|---|---|---|
| **1** | Infisical + Postgres + Redis in-cluster, UI reachable, admin login, backups | this spec |
| 2 | External Secrets Operator, `ClusterSecretStore`, one test secret | later |
| 3 | Migrate app secrets, plus `pg_dump` backup; scope decided after phase 1 | later |
| 4 | Ansible + Terraform on darth read from Infisical (day-2 only, never the bootstrap path) | later |

## 3. Decisions within this spec

- **Official Infisical chart (`infisical-standalone`), its bundled subcharts off.** The chart bundles Postgres and Redis as Bitnami subcharts using `bitnamilegacy/*` images, frozen since August 2025 (newest `bitnamilegacy/postgresql` tag: `17.6.0-debian-12-r4`, 2025-08-28). Set `postgresql.enabled: false`, `redis.enabled: false`, `ingress.enabled: false`, `ingress.nginx.enabled: false`.
- **Official `postgres:17` and `redis` images**, as plain manifests next to the chart. No operator (CloudNativePG considered, rejected as too heavy for one small database).
- **Postgres on Longhorn; Redis without persistence.** Infisical uses Redis only for cache and job queues.
- **Data-plane only.** Infisical, Postgres and Redis carry the `node-role.kubernetes.io/control-plane: DoesNotExist` node affinity used by Dex and Homepage.
- **Exposed like the other UIs:** a `LoadBalancer` Service with LB-IPAM IP `192.168.86.247` (pool `.241–.251`, `.241–.246` taken), a homekube-ca `Certificate` with that IP as SAN, and a static homepage entry (decision 074). No ingress controller.
- **Local admin login with 2FA.** OIDC SSO needs a paid licence on self-hosted ([Infisical docs](https://infisical.com/docs/documentation/platform/sso/general-oidc/overview)), so Dex can't be used.
- **Bootstrap secrets via sealed-secrets.** Infisical can't hold its own credentials.
- **Shared Longhorn backup job.** One `daily-backup` `RecurringJob` with `groups: [daily]`; PVCs opt in by label in their manifests. Avoids one job per app and fixes the drift found in #69.
- **Backups are crash-consistent volume snapshots.** Postgres recovers from them through WAL replay; the restore test (§7) is the proof. A `pg_dump` CronJob is added before phase 3 migrates real secrets.
- **No SMTP.** Single user; revisit if a feature needs it.
- **Upgrades: back up before merging.** Every Infisical version runs DB migrations at startup. Renovate doesn't auto-merge; merging an Infisical bump is preceded by a manual Longhorn backup of the Postgres volume. Postgres and Redis major bumps are disabled in Renovate; a Postgres major is its own piece of work (dump and restore).

## 4. Current state (verified 2026-11-01, re-verify before executing)

- `infisical/infisical` tags `v0.167.x` are published for `amd64` and `arm64`. Chart `infisical-standalone` `1.12.0` pins app `v0.167.0`.
- No ingress controller; UIs are `LoadBalancer` Services with fixed LB-IPAM IPs.
- Longhorn has one `RecurringJob` (`hermes-daily-backup`, `0 16 * * *`, `retain: 7`, no `groups`). Volumes opt in through PVC labels with `recurring-job.longhorn.io/source=enabled`.
- Velero is not deployed.
- Node memory: 30–41% used; limits overcommitted on two nodes (107%, 109%). The new pods add 416Mi requests / 1.4Gi limits on data-plane nodes; limits overcommit is accepted, as for the other apps.

## 5. Target state

All under `homekube-apps/applications/`. `infisical-extras/` is a second source on the `infisical` Application, as `dex-extras/` is on `dex`.

### 5a. `wave-02-apps/infisical.yaml`

ArgoCD `Application` for the `infisical-standalone` chart, namespace `infisical`, sync wave `2`, `CreateNamespace=true`, second source `applications/wave-02-apps/infisical-extras`. Added to `applications/kustomization.yaml`. Values:

- subcharts and ingress disabled (§3)
- `infisical.kubeSecretRef` → the sealed secret in 5b
- `SITE_URL=https://192.168.86.247`
- resources: requests `256Mi` / `50m`, limits `768Mi` / `500m`
- data-plane node affinity (§3)
- `fullnameOverride: infisical`, so the Service is `infisical.infisical.svc` and matches the DNS SAN in 5c
- Service `type: LoadBalancer`, annotation `io.cilium/lb-ipam-ips: "192.168.86.247"` (if the chart's Service can't take this, add a separate Service in 5b, as `argocd-extras/argocd-service.yaml` does)

### 5b. `wave-02-apps/infisical-extras/`

| File | Content |
|---|---|
| `infisical-sealedsecret.yaml` | `ENCRYPTION_KEY`, `AUTH_SECRET`, `DB_CONNECTION_URI`, `REDIS_URL` |
| `postgres-sealedsecret.yaml` | `POSTGRES_PASSWORD` (plus user and DB name) |
| `postgres.yaml` | StatefulSet (1 replica, `postgres:17`), headless Service, `volumeClaimTemplates` on `longhorn` with labels `recurring-job.longhorn.io/source: enabled` and `recurring-job-group.longhorn.io/daily: enabled`; resources `128Mi` / `25m` → `512Mi` / `500m`; data-plane node affinity (§3) |
| `redis.yaml` | Deployment (1 replica, `redis`), ClusterIP Service, no PVC; resources `32Mi` / `10m` → `128Mi` / `200m`; data-plane node affinity (§3) |

Image tags pinned and tracked by Renovate, minor and patch only. `renovate.json` gains:

```json
{
  "description": "Postgres/Redis majors need a manual data migration",
  "matchDatasources": ["docker"],
  "matchDepNames": ["postgres", "redis"],
  "matchUpdateTypes": ["major"],
  "enabled": false
}
```

`ENCRYPTION_KEY`: `openssl rand -hex 16`. `AUTH_SECRET`: `openssl rand -base64 32`. `POSTGRES_PASSWORD`: `openssl rand -hex 24` (hex, as it is embedded in `DB_CONNECTION_URI`). All three generated on darth and stored in the password manager **before** sealing.

### 5c. TLS

`wave-02-apps/infisical-extras/infisical-tls.yaml`, modelled on `wave-00-init/cert-manager/grafana-tls.yaml`: IP SAN `192.168.86.247`, DNS SAN `infisical.infisical.svc.cluster.local`, issued by the homekube CA. It lives in `infisical-extras/` rather than `wave-00-init/` because the `infisical` namespace doesn't exist at wave 0 on a fresh rebuild.

### 5d. Longhorn shared backup job

`wave-01-apps/longhorn-extras/recurring-jobs.yaml` gains:

```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: daily-backup
  namespace: longhorn-system
spec:
  cron: "0 16 * * *"
  task: backup
  groups:
    - daily
  retain: 7
  concurrency: 1
```

`hermes-daily-backup` stays until #69 moves Hermes over.

### 5e. Homepage

Static entry in `wave-03-apps/homepage/configmap.yaml` (decision 074).

## 6. Execution plan

0. **Verify:** latest chart version and its app version; the env var names the chart expects in `kubeSecretRef`; Postgres and Redis versions Infisical supports; whether the chart's Service accepts `type` and annotations, and honours `fullnameOverride` for its name; how TLS is served (§8 Q1); reclaim policy of the `longhorn` StorageClass; how DB migrations run (Helm hook Job or at backend startup).
1. Generate secrets on darth, save them in the password manager, seal them with `kubeseal` for namespace `infisical`. *(human step)*
2. PR to `homekube-apps`: 5a–5e. Review, merge, let ArgoCD sync.
3. Check pods are Ready (Infisical restarting until Postgres is up is expected), the DB migrations completed (hook result or Infisical logs, per step 0), and the Postgres PVC carries the backup labels on the Longhorn volume.
4. Open `https://192.168.86.247`, create the admin account, turn on 2FA. *(human step)*
5. Create a test project and secret in the UI.
6. Trigger a manual Longhorn backup of the Postgres volume and wait for it to finish.
7. Test restore (§7, last item).
8. Check the identity limit on self-hosted free (§8 Q2).
9. CHANGELOG entry; set this spec to Done.

## 7. Acceptance criteria

- [ ] `infisical`, `postgres` and `redis` pods Ready on arm64; no `bitnamilegacy` image in the namespace
- [ ] UI reachable at `https://192.168.86.247` with a homekube-ca-trusted certificate
- [ ] Admin login with 2FA works; test secret created and read back
- [ ] `ENCRYPTION_KEY`, `AUTH_SECRET` and `POSTGRES_PASSWORD` are in the password manager
- [ ] The Postgres Longhorn volume is in group `daily` and has at least one completed backup in S3
- [ ] Measured memory stays within the limits in §5 over the first week
- [ ] Homepage shows Infisical
- [ ] **Restore test:** the Postgres backup is restored to a new Longhorn volume and bound to a PVC in a throwaway namespace (Longhorn UI → Create PV/PVC). Postgres, Redis and Infisical run there from plain Secrets built from password-manager values (sealed secrets are namespace-scoped). Infisical shows the test secret. Manifests used are committed to `homekube-apps/manual/infisical-restore/`. Throwaway namespace and restored volume deleted afterwards.

## 8. Open questions for Jan

1. **TLS serving.** Grafana, ArgoCD and Dex serve TLS themselves. If Infisical's backend can't load a cert (to verify in step 0), the options are a small TLS-terminating sidecar in the Infisical pod, or plain HTTP on the LB IP. The sidecar keeps the cluster pattern; plain HTTP would put admin credentials on the LAN unencrypted.
2. **Identity limit.** The pricing page lists 5 identities (users + machine) on the free tier, apparently for Cloud. If self-hosted free has the same cap, phase 2 and the Coder/Hermes plan need re-thinking before they're specced.

## 9. Rollback

Delete the `infisical` Application (its finalizer removes everything in both sources), then the `infisical` namespace, which takes the Postgres PVC with it. With the `longhorn` StorageClass's `Delete` reclaim policy (verified in step 0), the Longhorn volume goes too. Longhorn backups in S3 are kept; delete them in the Longhorn UI if no longer wanted. Remove the homepage entry. Nothing depends on Infisical in phase 1. The `daily-backup` job can stay, as it only affects labelled volumes.

## 10. Out of scope

ESO and any consumer of Infisical (phase 2), migrating existing secrets (phase 3), darth/Ansible/Terraform integration (phase 4), OIDC login, SMTP, HA.
