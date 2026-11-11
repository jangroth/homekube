# Spec 011 — Coder install

**Status:** Done (2026-11-10)
**Related decisions:** [Decision 079](../../DECISIONS.md) — Infisical adopted for the Coder + Hermes goal. [Decision 080](../../DECISIONS.md) — Agent Vault; egress NetworkPolicy deferred to the Coder work. [Decision 039](../../DECISIONS-2026-Q3.md) — Dex issuer on `.ts.net`. [Decision 074](../../DECISIONS.md) — static homepage entries.
**Related specs:** [Spec 009](009-infisical-phase-1.md) — Postgres, TLS and backup patterns reused here. [Spec 010](010-agent-vault-hermes.md) — Agent Vault for Hermes.

---

## 1. Problem

Hermes should be able to start isolated workspaces to run code in, with credentials brokered by Agent Vault rather than held in the workspace. Coder provides the workspaces: a control plane (`coderd`) that provisions Terraform-defined workspaces as pods, each running an agent that connects back for terminal, SSH and apps.

This spec installs Coder and proves one hand-driven workspace, so the Pi-specific problems (arm64, homekube-ca trust, no ingress controller, resources) surface before anything automates it.

Workspaces are small, headless shells: SSH and the web terminal, no IDE or browser apps. The cluster is four 8GB Pis that already run the platform, so a workspace should cost little more than its agent at idle and burst only while it builds.

## 2. Phases

| Spec    | Scope                                                                                     |
| ------- | ----------------------------------------------------------------------------------------- |
| **011** | `coderd` + Postgres, Dex login, one Kubernetes template, one workspace driven by hand     | this spec |
| 012     | Workspace egress: Aperture path, GitHub App credential via Agent Vault, egress NetworkPolicy, OpenCode ([spec 012](012-workspace-egress.md)) | later |
| 013     | Hermes drives Coder over `coder ssh`, one workspace per task, a PR as the result          | later     |
| 014     | The issue loop: Hermes works `agent-safe` issues on a schedule                            | later     |

## 3. Decisions within this spec

- **Small headless workspaces.** A minimal image (agent, shell, git, curl) and small requests with burst limits; size is set by what runs in the workspace, not by Coder. Anything heavier is a template parameter, not the default. The decisions below on image, sizing, apps and access URL follow from this.
- **Official `coder` chart** from `https://helm.coder.com/v2`, namespace `coder`, sync wave `3` (after Dex, wave `2`). The chart has no bundled database.
- **Own Postgres**, not Infisical's: an Infisical migration or restore must not take Coder down. Plain `postgres:17` StatefulSet as in spec 009; Infisical's measures 7m / 120Mi, so the cost is upkeep, not resources. A third Postgres consumer is the point to reconsider one shared instance or CloudNativePG.
- **Exposed like the other UIs:** the chart's own `LoadBalancer` Service with `io.cilium/lb-ipam-ips: 192.168.86.248` (`.241–.247` taken), homekube-ca `Certificate` with that IP as SAN. `coderd` terminates TLS itself via `coder.tls.secretNames`; no sidecar. `CODER_ACCESS_URL=https://192.168.86.248`. An IP is fine because the OIDC callback is registered with Dex, not Google (decision 039 only binds Dex's own callback).
- **No wildcard access URL.** Subdomain apps need wildcard DNS; workspaces are used through the web terminal and `coder ssh` only.
- **Dex login.** Static client `coder` with its secret sealed and read by Dex via `secretEnv`, since `homekube-apps` is public. `CODER_OIDC_ISSUER_URL=https://pi0.taild13083.ts.net/dex`; in-cluster it resolves to the Dex VIP through the CoreDNS `hosts` entry, which serves a homekube-ca cert, so `coderd` trusts homekube-ca (below). `CODER_OIDC_ALLOW_SIGNUPS=false`.
- **Secrets sealed for now.** `coder-secrets`, `postgres-credentials` and `dex-coder-client` are not bootstrap tier (decision 079); they move to the Infisical operator in phase 3 under the same names, so the chart values don't change.
- **Two owners: a password break-glass user and the daily OIDC user.** Coder emails are unique, so the break-glass owner, created through the setup page, uses a `+breakglass` alias; its password goes in the password manager. With signups off, the daily user is pre-created with `coder users create --login-type oidc` and promoted with `coder users edit-roles --roles owner`; Dex login then links to it by email. "Convert to OIDC" in account settings is not used: it removes the password. Disabling password login waits until OIDC is proven, as for ArgoCD and Grafana.
- **homekube-ca trust in `coderd`:** a `homekube-ca` ConfigMap (same PEM as `prometheus-extras/`) mounted at `/etc/homekube-ca`, `SSL_CERT_DIR=/etc/homekube-ca`. Go then loads the system bundle file plus that directory, so public TLS (Terraform registry) keeps working.
- **homekube-ca trust in workspaces without root:** an init container concatenates the image's system bundle and homekube-ca into an `emptyDir`; the workspace container points `SSL_CERT_FILE` and `CURL_CA_BUNDLE` at it, which covers the agent download (curl) and the agent (Go). No `sudo`, `allowPrivilegeEscalation: false`.
- **Workspaces in their own namespace `coder-workspaces`**, managed through the chart's `serviceAccount.workspaceNamespaces` (Role + RoleBinding, no ClusterRole). `workspacePerms` off in `coder` itself. The namespace is a manifest in `coder-extras/`, so it exists before the chart's Role.
-
- **Built-in provisioner, one daemon** (`CODER_PROVISIONER_DAEMONS=1`): Terraform runs in the `coderd` pod; one at a time bounds memory.
- **Telemetry off** (`CODER_TELEMETRY_ENABLE=false`).
- **Coder's default GitHub providers off** (`CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE=false`; external auth through the flag `--external-auth-github-default-provider-enable=false`, since its env name is parsed as a numbered `CODER_EXTERNAL_AUTH_<n>_*` provider and fails startup). A new deployment otherwise enables GitHub login through Coder's own app for any GitHub account, and the first user can sign up whatever the signup settings say.
- **Data-plane only** for `coderd`, Postgres and workspace pods (`node-role.kubernetes.io/control-plane: DoesNotExist`).
- **Template in git, pushed by hand.** `homekube-apps/manual/coder-templates/kubernetes/main.tf`, pushed with `coder templates push`. The template is Coder state, not a Kubernetes object, so ArgoCD can't own it. Changes go to git first, then are pushed; the template is never edited in the UI.
- **Template shape:** one pod and a home PVC on `longhorn`. Image `codercom/example-base` pinned to a dated tag (`ubuntu-20261105`): heavier than needed (§4), accepted as a start; a slimmer image replaces it once size matters. Requests `100m` / `128Mi` (idle `dev` measured 50–84Mi, 26m peak), limits `1` CPU / memory limit as the only parameter (`1Gi` default, `2Gi`); home `2Gi`. Home PVCs are not in a backup group: workspaces are disposable, work lives in git.
- **Upgrades: back up before merging**, as for Infisical: `coderd` runs DB migrations at startup. Coder chart bumps get their own Renovate PR, outside the grouped Helm chart PR, so the backup step isn't skipped. The existing rule already blocks Postgres majors.

## 4. Current state (verified 2026-11-08)

- Chart index: `2.39.0` newest (mainline), released 2026-11-03. Image `ghcr.io/coder/coder:v2.39.0` publishes `linux/arm64`.
- `coderd` image (Alpine) bundles Terraform `1.17.1` for arm64 (`scripts/Dockerfile.base`); no download at runtime.
- Chart: `coder.service` is `LoadBalancer` with `annotations`; `coder.tls.secretNames` sets `CODER_TLS_*` and listens on 8443; `serviceAccount.workspaceNamespaces` creates per-namespace Roles; `coder.resources` unset by default.
- OIDC login is not licence-gated (only SCIM is Premium in the OIDC docs).
- Pre-created OIDC user: with no existing link, the first login matches by email; an existing user skips the signup gate, and its `oidc` login type matches. Dex passes Google's `email_verified`, which Coder requires.
- Go (`crypto/x509`): `SSL_CERT_DIR` replaces only the directory list; the bundle file (`/etc/ssl/cert.pem` on Alpine) is still loaded. ConfigMap key symlinks (`ca.crt -> ..data/ca.crt`) are read; only symlinks without `/` in the target are skipped.

- Dex `v2.46.0` (chart `0.26.0`) supports `secretEnv` on static clients (`storage.Client.SecretEnv`). Dex `envFrom` today: `dex-google-oauth`.
- `codercom/example-base` publishes `linux/arm64` with dated tags (`ubuntu-20261105`), but is 373 MB compressed with docker, systemd, build-essential and `sudo NOPASSWD` (inert under `allowPrivilegeEscalation: false`). `buildpack-deps:trixie-scm` is 142 MB (curl, git, ssh, ca-certificates), runs as root with no uid 1000 user, and is pinnable only by digest.
- LB-IPAM pool `.241–.251`, `.241–.247` taken; `.248` free.
- Node memory 32–47% used.
- Pods reach the Dex VIP `.244` by the `.ts.net` name (CoreDNS `hosts` entry); Dex serves homekube-ca cert `dex-tls`.
- Existing Dex clients `argocd` and `grafana` have literal secrets in the public repo (not changed here).
- Renovate's managers only scan `applications/**.yaml`; the `argocd` minor/patch rule groups all chart bumps into one PR.
- Not verifiable before deploy: agent download from `https://192.168.86.248` with the combined bundle via `CURL_CA_BUNDLE`; checked in step 2.

## 5. Target state

All under `homekube-apps/applications/` unless noted. `coder-extras/` is a second source on the `coder` Application, as `infisical-extras/` is on `infisical` (wave 2).

### 5a. `wave-03-apps/coder.yaml`

ArgoCD `Application` for chart `coder`, namespace `coder`, sync wave `3`, `CreateNamespace=true`, second source `applications/wave-03-apps/coder-extras`. Added to `applications/kustomization.yaml`. Values:

- `coder.env`: `CODER_ACCESS_URL`, `CODER_OIDC_ISSUER_URL`, `CODER_OIDC_CLIENT_ID=coder`, `CODER_OIDC_ALLOW_SIGNUPS=false`, `CODER_OIDC_SIGN_IN_TEXT`, `CODER_PROVISIONER_DAEMONS=1`, `CODER_TELEMETRY_ENABLE=false`, `CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE=false`, `SSL_CERT_DIR=/etc/homekube-ca`
- `coder.commandArgs`: `server`, `--external-auth-github-default-provider-enable=false`
- `coder.envFrom`: secret `coder-secrets` (`CODER_PG_CONNECTION_URL`, `CODER_OIDC_CLIENT_SECRET`)
- `coder.tls.secretNames: [coder-tls]`
- `coder.service.annotations`: `io.cilium/lb-ipam-ips: "192.168.86.248"`
- `coder.serviceAccount`: `workspacePerms: false`, `workspaceNamespaces: [{name: coder-workspaces, workspacePerms: true, enableDeployments: false}]`
- `coder.volumes` / `volumeMounts`: ConfigMap `homekube-ca` at `/etc/homekube-ca`
- resources: requests `256Mi` / `100m`, limits `1Gi` / `1000m`. Measured (step 6): idle 177Mi, peak 334Mi during a workspace build, CPU peak 127m; limit kept for plan spikes shorter than a scrape
- data-plane node affinity

### 5b. `wave-03-apps/coder-extras/`

| File                         | Content                                                                                                                                                                            |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `namespace-workspaces.yaml`  | Namespace `coder-workspaces`                                                                                                                                                       |
| `coder-sealedsecret.yaml`    | Secret `coder-secrets`: `CODER_PG_CONNECTION_URL`, `CODER_OIDC_CLIENT_SECRET`                                                                                                      |
| `postgres-sealedsecret.yaml` | Secret `postgres-credentials`: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`                                                                                                 |
| `postgres.yaml`              | As spec 009 5b: StatefulSet `postgres:17.x`, headless Service, 5Gi PVC on `longhorn` in the `daily` backup group; resources `128Mi` / `10m` → `256Mi` / `250m` (measured 57–75Mi); data-plane affinity |
| `coder-tls.yaml`             | homekube-ca `Certificate`: IP SAN `192.168.86.248`, DNS SANs `coder.coder.svc` and `coder.coder.svc.cluster.local`                                                                 |
| `homekube-ca-configmap.yaml` | ConfigMap `homekube-ca` in `coder` and in `coder-workspaces`                                                                                                                       |

`POSTGRES_PASSWORD` (`openssl rand -hex 24`) and the Dex client secret (`openssl rand -hex 32`) generated on darth and stored in the password manager **before** sealing.

### 5c. Dex

`wave-02-apps/dex.yaml`: static client `coder`, `secretEnv: CODER_CLIENT_SECRET`, redirect URI `https://192.168.86.248/api/v2/users/oidc/callback`; `envFrom` gains sealed secret `dex-coder-client` (in `dex-extras/`).

### 5d. Template

`homekube-apps/manual/coder-templates/kubernetes/main.tf`: providers `coder/coder` and `hashicorp/kubernetes` (in-cluster config), namespace `coder-workspaces`. Pod (`count = start_count`) with the image, resources and memory parameter from §3, data-plane affinity, the CA-bundle init container, `allowPrivilegeEscalation: false` and `runAsNonRoot: true` on each container (the provider writes a container-level `false` otherwise, overriding the pod's); PVC without `count`, so stop keeps it and delete removes it; `coder_agent` whose init script runs in the workspace container. The image line carries a `# renovate:` comment for the regex manager in 5f.

### 5e. Homepage

Static entry `https://192.168.86.248` with `siteMonitor: https://coder.coder.svc` in `wave-03-apps/homepage/configmap.yaml`.

### 5f. Renovate (`homekube-apps/renovate.json`)

- Regex manager for `manual/coder-templates/**/*.tf`, matching the `# renovate:` comment above the image line.
- The Helm minor/patch group rule excludes chart `coder` (`"matchPackageNames": ["!coder"]`), so Coder bumps arrive as their own PR.

## 6. Execution plan

0. **Verify:** chart version and channel (mainline, §8); OIDC login works on the unlicensed build; Dex `secretEnv` on static clients in the deployed Dex version; a pre-created `--login-type oidc` user is linked on first Dex login with signups off; Go honours `SSL_CERT_DIR` alongside the system file in the `coderd` image; the agent init script reaches `https://192.168.86.248` from a pod and trusts the combined bundle via `CURL_CA_BUNDLE`; `codercom/example-base:ubuntu` publishes `linux/arm64` (else `debian:stable-slim`) and has a pinnable tag; Terraform is bundled in the `coderd` image for arm64.
1. Generate secrets, store in the password manager, seal `coder-secrets` and `postgres-credentials` (namespace `coder`) and `dex-coder-client` (namespace `dex`). _(human step)_
2. PR to `homekube-apps`: 5a–5c, 5e, 5f. Merge, sync. Check `coderd` and Postgres are Ready, migrations ran, the PVC is in group `daily`.
3. Open `https://192.168.86.248`, create the break-glass owner with the `+breakglass` email (password into the password manager). `coder login` as it from darth, `coder users create --login-type oidc` for the daily user, `coder users edit-roles <user> --roles owner`, then log in through Dex as that user. _(human step)_
4. PR to `homekube-apps`: 5d. `coder templates push` from darth. _(human step)_
5. Create a workspace; open the web terminal; `coder ssh` from darth; stop and start it, home contents survive; delete it, pod and PVC are gone.
6. Measure `coderd` memory idle and during a template build (the first push may OOM at the `1Gi` limit); measure an idle workspace; adjust §5a and §3.
7. Manual Longhorn backup of the Postgres volume before the first Coder bump. Covered by the `daily` job (completed backups 2026-11-08 and 2026-11-09); the manual backup stays a pre-bump step.
8. CHANGELOG entry; decision entry; set this spec to Done.

## 7. Acceptance criteria

- [x] `coderd` and Postgres Ready on arm64, data-plane nodes only
- [x] UI at `https://192.168.86.248` with a homekube-ca-trusted certificate
- [x] Login through Dex works; new OIDC signups are refused (`CODER_OIDC_ALLOW_SIGNUPS=false`; refusal not tested, waived)
- [x] Break-glass owner password and Postgres password in the password manager
- [x] Template pushed from git; a workspace starts in `coder-workspaces`, its agent connects, web terminal and `coder ssh` from darth work
- [x] Workspace container runs without privilege escalation
- [x] Stop/start keeps the home volume; delete removes pod and PVC
- [x] `kubectl auth can-i --list --as=system:serviceaccount:coder:coder` shows no permissions in `default` beyond the defaults granted to all service accounts, and only the chart's Roles in `coder` and `coder-workspaces` (`kube-system` shows sealed-secrets' `services/proxy`, bound to `system:authenticated`)
- [x] Postgres volume is in group `daily` with one completed backup
- [x] Homepage shows Coder with a green site monitor
- [ ] A Coder chart bump arrives as its own Renovate PR (no chart release since 2.39.0; rule in place)

## 8. Resolved questions

1. **Release channel:** mainline (`2.39.x`), with Coder bumps in their own Renovate PR (5f).
2. **Workspace memory limit:** `1Gi` default, `2Gi` as the upper choice; revisited in spec 013 against real builds.

## 9. Risks

- **Memory during template builds.** Terraform runs in the `coderd` pod; provider downloads and plans spike memory. One provisioner daemon bounds it; measured in step 6.
- **Agent reachability.** The agent and `coder ssh` connect through `coderd` on the access URL (embedded DERP over HTTPS). Direct peer-to-peer connections from darth won't form across the tailnet/LAN boundary; relayed is enough for one user.
- **Template drift.** A template edited in the UI no longer matches git; the rule is git first, then push.
- **Workspace egress is open** until spec 012.
- **Licence creep.** Some features (group/role sync, quotas, workspace proxies) are Premium; this spec uses none.

## 10. Rollback

Delete workspaces in Coder, then the `coder` Application (finalizer removes both sources), then namespaces `coder` and `coder-workspaces`, which take the PVCs with them. Workspace pods and PVCs are Terraform-managed, not part of the Application: deleting them or their namespace before the workspaces leaves Coder's state pointing at nothing. Remove the Dex client and its secret, the homepage entry and the Renovate rules. Nothing depends on Coder yet.

## 11. Out of scope

Agent Vault in workspaces and egress NetworkPolicy (spec 012; the `agent-vault` ingress NetworkPolicy then needs `coder-workspaces` alongside `hermes`), Hermes driving Coder (spec 013), wildcard apps and DNS, code-server/IDE apps, disabling password login, HA, Coder's metrics in Prometheus.
