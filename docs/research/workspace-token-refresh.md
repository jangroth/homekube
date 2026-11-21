# Refreshing the workspace GitHub App tokens

Research for #90 (Research: how the workspace GitHub token gets refreshed), under #89 (Spec: workspace egress). Researched 2026-11-22 against the deployed versions: Infisical `v0.167.6` and the proxy image `infisical/cli:0.44.15` (`homekube-apps/applications/wave-03-apps/agent-vault/deployment.yaml`). Builds on [per-task-credentials.md](https://github.com/jangroth/homekube/blob/research/per-task-credentials/docs/research/per-task-credentials.md) from #102 (Research: per-task Agent Vault sessions and repo-narrowed App tokens), whose findings are not repeated here. Constraint from #107 (the per-task credential model): one bundle per onboarded repo, each holding a token narrowed to that repo.

Source abbreviations: **IS** = `github.com/Infisical/infisical` at tag `v0.167.6`; **IS-main** = the same repo on `main` at `163d351` (2026-11-21), only to see what is coming; **GH** = GitHub REST docs, API version 2022-11-28; **ESO** = external-secrets.io docs.

## Answer

| Question | Answer |
|---|---|
| Can a service credential reference an Infisical *secret*? | **No.** Agent Vault has no link to Secrets Management secrets or dynamic secrets. It can reference an Agent Vault **global variable** (`{{KEY}}`), and a writer can update the variable instead of PATCHing the service. |
| Who may write a global variable? | **Agent Vault Admin only.** The check is `Edit` on access bundles, the same right that PATCHing a service needs. No narrower role exists at `v0.167.6` or on `main`. |
| How fast does the proxy pick up a new value? | **Within one poll interval** (60 s default) for a variable or a service credential; no restart. |
| Minter shape | A CronJob holding the App key, minting one narrowed token per repo every 30 min and writing it to that repo's variable. Feasible with plain REST calls on both sides. |
| Off-the-shelf tool? | **None that writes to Agent Vault.** ESO's `GithubAccessToken` generator mints narrowed tokens but only into Kubernetes Secrets, and ESO isn't deployed. |
| Native GitHub App support in Agent Vault? | **No**, neither at `v0.167.6` nor on `main`. Its OAuth support needs a person signing in, which gives a user token, not the App's bot token. |

**Recommendation (the owner decides):** a minter CronJob writing one global variable per repo, authenticated with Infisical Kubernetes Auth as an Agent Vault Admin identity. Reasons and alternatives below.

## 1. Where a refreshed token can be written

### Global variables, not Infisical secrets

- A global variable is a key and a sealed value on the Agent Vault project. A service uses it as `{{KEY}}` in a bearer token, a basic username or password, a custom header value or a substitution value (IS `docs/documentation/platform/agent-vault/variables.mdx`, "Use a variable in a service"; IS `backend/src/ee/services/agent-vault/AGENTS.md`, "Variables").
- Values are sealed with the Agent Vault project's own KMS key (IS `backend/src/ee/services/agent-vault-variable/agent-vault-variable-service.ts:63`). Nothing in `agent-vault*` reads Secrets Management secrets or dynamic secrets; the only app connection is AWS, for session-log storage (per-task-credentials.md, "Where a credential can live"). This is still true on IS-main.
- So one variable per repo, e.g. `GH_TOKEN_AGENT_SANDBOX`, can feed both GitHub services of that repo's bundle: `api.github.com` as a bearer token `{{GH_TOKEN_AGENT_SANDBOX}}`, and `github.com` as basic with username `x-access-token` and password `{{GH_TOKEN_AGENT_SANDBOX}}`, the header shape spec 012 §3 settled for git smart HTTP. One write per repo then refreshes both.
- Limits: 500 global variables per project (variables.mdx), values up to 8192 characters and at most 3 references per field (AGENTS.md "Variables"). A `ghs_APPID_JWT` token fits (per-task-credentials.md).
- A stored value is never returned except by `GET /variables/:id/value`, which is audited per read (AGENTS.md "Variables", last bullet). A rename doesn't break services, because the sealed text names the variable by id (variables.mdx, "Update a variable" note).

### Write paths and the identity each needs

| Write | Route (prefix `/api/v1/agent-vault`) | Permission | Role holding it |
|---|---|---|---|
| Update a global variable | `PATCH /variables/:variableId`, body `{ "value": "<token>" }` (`operationId: updateAgentVaultVariable`) | `Edit` on `AgentVaultAccessBundles` (`agent-vault-variable-service.ts`, `resolveScope` and `findAccessibleVariable`; a member gets 404) | Admin |
| Update a service credential | `PATCH /access-bundles/:accessBundleId/services/:serviceId` (`operationId: updateAgentVaultService`) | Edit on bundles | Admin |
| Set own personal values | `PATCH /access-bundles/:id/services/:serviceId/personal-values` | Read on bundles plus a grant | Member (only for that actor's own sessions) |

All three accept a machine identity's access token (`verifyAuth([AuthMode.JWT, AuthMode.IDENTITY_ACCESS_TOKEN, AuthMode.OAUTH])`, IS `agent-vault-routers/agent-vault-variable-router.ts` and `agent-vault-access-bundle-router.ts:413`).

- **No narrower role.** Agent Vault has two roles, Admin and Member (IS `docs/documentation/platform/agent-vault/access-control.mdx`, "Product membership"). On IS-main every gate is a CASL action, but "in an Agent Vault project any role but admin resolves to the member set, custom roles and additional privileges included" (IS-main `AGENTS.md`, "Permissions"). A variable-only writer role does not exist yet.
- **What Admin also allows**: managing every bundle, service, variable and proxy, granting bundles, managing members, setting delegations and reading audit logs (access-control.mdx). It can read every global variable's value, which includes other brokered credentials such as Hermes's search key if those are ever moved into variables.
- **Personal values aren't a fit for the minter.** They are always the caller's own; no route writes another actor's, and a session uses its owner's values (AGENTS.md "Member-provided values"). They help only if the minter is also the identity that owns the workspace sessions; see alternative B.

### Pick-up time

- Changing a variable: "the proxy starts using the new value within one poll interval (60 seconds by default), so you don't need to restart running agents" (variables.mdx, "Update a variable"). Resolve expands variables from the decrypted fields on every resolve (AGENTS.md "Variables"), so a value change and a service change propagate the same way.
- Poll interval 10–300 s, set on the proxy; if Infisical is unreachable the proxy keeps the last data for five intervals, then returns 502 (IS `proxies.mdx:218-226`, via per-task-credentials.md). The homekube proxy runs the default 60 s (spec 010 §5b).
- Margin: a token minted at T is valid until T+60 min (GH, *Create an installation access token for an app*). Written at T and live in the proxy by T+1 min, a 30-minute schedule leaves one missed run of slack before workspaces see 401s.

## 2. The minter

### Shape

A Kubernetes CronJob in its own namespace (spec 012 already sketches `wave-03-apps/github-app-minter/`):

1. **Schedule** `*/30 * * * *`, `concurrencyPolicy: Forbid`, a `startingDeadlineSeconds` below 30 min, `backoffLimit` of 1 or 2, and a short `activeDeadlineSeconds`.
2. **Inputs**: sealed Secret `github-app` (App or client ID, installation ID, private key), and a ConfigMap mapping each onboarded repo to its Agent Vault variable key, kept in git so onboarding a repo is a PR.
3. **GitHub side**, for each repo:
   - Build a JWT, RS256, `iat` 60 s in the past, `exp` at most 10 min ahead, `iss` the client ID (GH, *Generating a JSON Web Token (JWT) for a GitHub App*). One JWT serves the whole run.
   - `POST /app/installations/{installation_id}/access_tokens` with `{"repositories":["<repo>"],"permissions":{"contents":"write","pull_requests":"write"}}`. The token can't exceed what the installation holds; the repo must already be one of the installation's selected repos (GH, same section; ADR-0019).
   - Check that the response's `repositories` holds exactly that one repo and its `permissions` match, so a mistake fails loudly instead of widening the scope.
4. **Infisical side**:
   - Log in with **Kubernetes Auth**: the pod posts its service account JWT to `/api/v1/auth/kubernetes-auth/login`, Infisical checks it through the TokenReview API against the identity's allowed service account names and namespaces, and returns a short-lived access token (Infisical docs, *Kubernetes auth*, "Concept"). No static client secret to seal or rotate.
   - `PATCH /api/v1/agent-vault/variables/:variableId` with `{"value": "<token>"}` per repo. The variable ids can be looked up once per run with `GET /variables?scope=global` and matched by key, which keeps ids out of the ConfigMap.
5. **Failure visibility**: one stdout line per repo (repo, result, token `expires_at`, never the token itself), which Loki picks up. Exit non-zero if any repo failed, after trying the others, so the Job is marked failed. Each variable update is also an `AGENT_VAULT_VARIABLE_UPDATE` audit event in Infisical (variable router, PATCH handler).

Secrets stay where #90 requires them: the private key lives only in the minter's Secret, and the real tokens only in the minter's memory and in Infisical. Workspaces and Hermes hold session tokens only.

### Least-privilege identity

- One Infisical machine identity, `github-app-minter`, with Kubernetes Auth bound to service account `github-app-minter` in the minter's namespace only.
- Agent Vault role **Admin**, since nothing smaller can write a global variable or a service (§1). No membership in any Secrets Management project and no org-level role beyond what the identity needs to exist.
- Containment comes from Kubernetes rather than Infisical: a dedicated namespace, no ingress, an egress policy allowing only `api.github.com` and Infisical, and RBAC so that only the owner can read the Secret and exec into the pod.
- Later on IS-main, Agent Vault **projects** ("Keep each agentic system's credentials and members in a separate Agent Vault project", IS-main `docs/documentation/platform/agent-vault/projects.mdx`) would let the minter be Admin of a workspace-GitHub project only. At `v0.167.6` the open-source edition can't create a second project (spec 010 §5b). Whether the feature reaches the open-source edition is untested.

### Off-the-shelf tools

- **ESO `GithubAccessToken` generator**: mints installation tokens with optional `repositories` and `permissions` from an App key held in a Kubernetes Secret (ESO, *Github* generator, example manifest). It writes to Kubernetes Secrets, not to Agent Vault, and ESO isn't deployed in homekube-apps. Using it would still need a second component to copy each Secret into Agent Vault, so it adds an operator without removing the script.
- **Infisical GitHub dynamic secret**: posts to `/access_tokens` with no body, so it can't narrow, and Agent Vault can't consume it anyway (per-task-credentials.md, "Note for #90").
- `actions/create-github-app-token` and similar run only inside GitHub Actions. Nothing found writes into Agent Vault, so the minter is a short script: `openssl`, `curl` and `jq`, or Python with `PyJWT` (GH JWT docs show a Python example).

## 3. Alternatives

| | Shape | For | Against |
|---|---|---|---|
| **Recommended** | Minter PATCHes one global variable per repo, both repo services reference it | One write per repo; the minter never touches host, path or method rules; services stay as an admin defined them | Admin identity; global variables are visible to every Admin |
| A | Minter PATCHes the two services of each repo bundle | No variables to create | Two writes per repo; the minter needs bundle and service ids and has to update the basic credential's password without disturbing its username (a partial basic update merges against the stored secret and 409s if that changed mid-save, AGENTS.md "Variables"); same Admin role |
| B | Session-owning identity as minter, writing its **personal values** (Member role) | No Admin; personal values can't be read back, only their status (IS-main AGENTS.md "Member-provided values", "Reads ride along") | Works only for sessions that identity owns. Today's workspace session is created by a person in the UI (spec 012 §6 step 1, as for Hermes in spec 010 §4), so its owner's values can't be written by a machine. When per-task sessions come (spec 013), the orchestrator's identity would need the minter's write access too. Two writes per repo (personal variables would make it one, but their values can be read by the owner). The UI doesn't cover identities' personal values; untested. |
| C | Infisical GitHub dynamic secret | No custom code | Can't narrow; not consumable by Agent Vault. Ruled out. |
| D | Agent Vault native | Refresh handled by Infisical | Doesn't exist for GitHub App installation tokens. Service OAuth is for MCP services only (IS `AGENTS.md` "OAuth credentials"). IS-main's OAuth variables use only the Authorization Code grant, where a person signs in; Client Credentials is a listed follow-up (IS-main `AGENTS.md` "Follow-ups"), and an installation token is minted with a signed JWT, not an OAuth grant. A person's sign-in gives a user-to-server token that acts as the owner, so PRs wouldn't be authored by `homekube-agent[bot]` (ADR-0019). IS-main hooks only allow or refuse a request; they don't provide credentials (IS-main `AGENTS.md` "Hooks"). |

## Caveats

- Nothing here was exercised against the cluster. The variable route, role check and pick-up time come from source and docs at `v0.167.6`.
- The minter is a long-lived Admin in Agent Vault. A compromised minter pod could repoint services or read variable values. The Kubernetes containment above is the only boundary until Agent Vault offers narrower roles or separate projects.
- Old tokens are not revoked on refresh; each simply expires an hour after minting. Revoking the previous token (`DELETE /installation/token`, authenticated with that token) right after a write would cut off proxy pods still polling the old value, so if it's ever wanted it should wait more than one poll interval.
- If the minter stops, every repo's token expires within an hour of the last good run, and workspaces get `401` from GitHub through the proxy. Alerting on a failed Job (or on no successful Job for 45 min) catches this before that happens.
