# Per-task Agent Vault sessions and repo-narrowed App tokens

Research for #102 (Research: per-task Agent Vault sessions and repo-narrowed App tokens), under #100. Researched 2026-11-21 against the deployed versions: Infisical `v0.167.6` (`homekube-apps/applications/wave-02-apps/infisical.yaml`) and the proxy image `infisical/cli:0.44.15` (`wave-03-apps/agent-vault/deployment.yaml`). How the token is refreshed before its hour runs out is #90 (Research: how the workspace GitHub token gets refreshed) and is not repeated here.

Source abbreviations: **IS** = `github.com/Infisical/infisical` at tag `v0.167.6`; **CLI** = `github.com/Infisical/cli` at tag `v0.44.15`; **GH** = GitHub REST docs, API version 2022-11-28.

## Answer

| Question | Answer |
|---|---|
| Sessions created per task through an API, with a TTL? | **Yes.** `POST /api/v1/agent-vault/sessions` as a machine identity, `ttl` from `1m` to 100 years or `never`, default `7d`. |
| Sessions revoked per task through an API? | **Yes.** `POST /api/v1/agent-vault/sessions/:sessionId/revoke`; the proxy stops attaching credentials within one poll interval. |
| Bundles created and deleted per task through an API? | **Yes, but only by an Agent Vault Admin.** Full CRUD on bundles, their services and grants exists; creating them is an Admin-only action. |
| Installation token narrowed to one repo per task? | **Yes.** `repositories` / `repository_ids` and `permissions` on `POST /app/installations/{id}/access_tokens`. Lifetime is fixed at one hour. |
| Can Agent Vault carry a per-task credential? | **Not per session.** A credential lives on a service (so per bundle) or in the personal values of the session's owner. Per-task means a per-task bundle or a per-slot identity, both written by an orchestrator through the API. Agent Vault cannot mint GitHub App tokens itself. |

## Sessions

- **Create.** `POST /api/v1/agent-vault/sessions`, body `accessBundles` (a list), `ttl`, `label`, optional `onBehalfOf`. Authenticated as a user or machine identity (IS `docs/documentation/platform/agent-vault/sessions-api.mdx`, Step 3; route in IS `backend/src/ee/routes/v1/agent-vault-routers/agent-vault-session-router.ts`, `operationId: createAgentVaultSession`).
- **TTL.** At least one minute (`30m`, `8h`, `7d`) or `never`, at most 100 years; default `7d`, or `1h` for an on-behalf-of session (IS `backend/src/ee/services/agent-vault-session/agent-vault-session-service.ts:35-43`, and the router's `superRefine` on `ttl`). Expiry is checked against the clock on every resolve (IS `backend/src/ee/services/agent-vault/AGENTS.md:120-121`).
- **One bundle per session.** `accessBundles` is a list but `AGENT_VAULT_MAX_SESSION_BUNDLES = 1` (IS `agent-vault-session-service.ts:35`; AGENTS.md:92 calls it a V1 cap). GLOSSARY.md's "exactly one bundle" holds.
- **Token handling.** Returned once, stored as sha256 (AGENTS.md "Sessions and resolve"). Response carries `id`, `label`, `token`, `expiresAt`.
- **Revoke.** `POST /api/v1/agent-vault/sessions/:sessionId/revoke` (router as above; sessions-api.mdx Step 5, which recommends revoking in a `finally` and falling back on the TTL). The creating machine identity can revoke its own sessions; a Member can revoke only their own (IS `docs/documentation/platform/agent-vault/access-control.mdx:29`).
- **Label.** `PATCH /api/v1/agent-vault/sessions/:sessionId`, up to 128 characters, editable after expiry (IS `sessions.mdx`, "Label a session"). Useful to tie a session to a task or issue number.
- **Sessions are never deleted** (AGENTS.md "Sessions and resolve"), so per-task sessions leave a full audit history.
- **CLI alternative.** `infisical agent-vault run --access-bundle <b> --ttl <d> --label <l>` creates the session and revokes it on exit unless `--keep-session` (IS `sessions.mdx`, CLI tab). Not usable for homekube workspaces as is: it needs a machine identity in the agent's environment, which spec 010 §4 rules out.

### How the proxy picks up a change

- A session token the proxy hasn't seen is resolved on first use; concurrent misses share one resolve (CLI `packages/agentvault/cache.go:123`). A freshly minted session works immediately.
- Known sessions are re-resolved every poll interval, default 60 s, settable 10-300 s (IS `docs/documentation/platform/agent-vault/proxies.mdx:218-226`). Revocation, expiry of a grant and a changed credential all take effect within one interval. A definitive refusal is cached briefly (CLI `cache.go:134`).
- If Infisical is unreachable the proxy keeps the last data for five poll intervals, then answers 502 rather than forwarding without credentials (proxies.mdx:224-225). A revoked session can therefore live up to ~5 minutes during an Infisical outage at default settings.

## Bundles and services

- Routes (IS `agent-vault-routers/agent-vault-access-bundle-router.ts`): `GET/POST /access-bundles`, `GET/PATCH/DELETE /access-bundles/:id`, `POST/PATCH/DELETE /access-bundles/:id/services[/:serviceId]`, `POST/DELETE /access-bundles/:id/members` (grants), `PATCH/DELETE .../services/:serviceId/personal-values`. All accept machine-identity tokens (`AuthMode.IDENTITY_ACCESS_TOKEN`, e.g. line 328).
- **Admin only.** Creating and managing bundles, services, variables and proxies, and granting bundles, is the Agent Vault **Admin** role; a **Member** can only create sessions on bundles granted to it, revoke its own sessions and set its own personal values (IS `access-control.mdx:28-29`). An Admin also uses every bundle without a grant and can set delegations, including one for itself covering every member (IS `sessions-on-behalf-of-users.mdx`, Warning).
- Deleting a bundle deletes its grants, services and their values in one transaction (AGENTS.md "Grants and reachability"). The bundle on a session is fixed at mint and intersected with live reachability on every resolve, so deleting a bundle after revoking its session is safe.

## Where a credential can live

The resolve response the proxy receives lists, per service, one credential (`bearer`, `basic`, `passthrough`; OAuth is delivered in the bearer shape) plus custom headers and substitutions (IS `agent-vault-proxy-agent-router.ts:139-187`; enum in `backend/src/ee/services/agent-vault/agent-vault-enums.ts`). There is no per-session field. A value comes from one of:

1. **The service itself** (admin-set). Per bundle.
2. **A global variable** `{{KEY}}` referenced from the service. One value for every bundle and session that uses it; changing it reaches running proxies within a poll interval (IS `docs/documentation/platform/agent-vault/variables.mdx`). Not per task.
3. **Member-provided ("personal") values.** The admin leaves the bearer token or either half of a basic credential to each member (`memberProvidedFields`); each actor saves its own values, and a session uses the values of whoever owns it, or of the user it was minted on behalf of (AGENTS.md:370-380). The owner may be a machine identity, through the API only (AGENTS.md:397). An actor can only set its **own** values; no route writes another actor's (AGENTS.md "Member-provided values"). Custom-header and substitution values cannot be member-provided yet.
4. **OAuth** authorizations, refreshed by Infisical, for MCP-style services (AGENTS.md "OAuth credentials"). Not applicable to a GitHub App installation token.

Agent Vault has no GitHub App integration and no reference to Infisical secrets or dynamic secrets: its only app connection is AWS (IS `agent-vault-app-connection-router.ts`), and a grep of `backend/src/ee/services/agent-vault*` for `github` or `dynamic` finds only OAuth code. Whatever mints the per-task token has to write it into Agent Vault through the API.

### Ways to get a per-task credential

| Shape | Who writes the token | Isolation | Cost |
|---|---|---|---|
| **Per-task bundle**: orchestrator creates bundle + `github.com`/`api.github.com` services holding the narrowed token, mints a session, revokes it and deletes the bundle at the end | Orchestrator machine identity, **Admin** role | One bundle per task; concurrent tasks don't share | Orchestrator holds Agent Vault Admin. Refresh past the hour means `PATCH` on the task's services. |
| **Per-slot identity**: one shared bundle whose GitHub services leave the credential member-provided; a pool of machine identities (Member role, granted the bundle), one per concurrent task; the orchestrator logs in as the slot's identity, sets its personal values to the task's token and mints the session as that identity | Each slot identity, **Member** role | Per slot, so per task while a slot runs one task at a time | N identities and their client secrets for N concurrent tasks; a slot's next task must overwrite its values before its session is minted. |
| Shared global variable | Admin | None: every session sees the same token | Ruled out for per-task. |
| On behalf of users | Delegated machine identity | Per Infisical *user* | Needs a real user per task; doesn't fit. |

Both workable shapes keep the App private key and the real token in the orchestrator and in Infisical only; the workspace still holds only a session token. Neither is tested yet.

## GitHub App installation tokens

- `POST /app/installations/{installation_id}/access_tokens`, authenticated with the App's JWT. Body `repositories` (names) or `repository_ids`, up to 500, and `permissions` (e.g. `{"contents":"write","pull_requests":"write"}`). Without them the token gets every repo of the installation and every App permission; with them it can never exceed what the installation was granted (GH "REST API endpoints for GitHub Apps", *Create an installation access token for an app*).
- **One repo per task works**: pass that single repo name and the narrowed permissions. The repo must already be in the installation's selected repositories (ADR-0019: installed on `agent-sandbox` only, real repos added one by one).
- **Lifetime is fixed at one hour** from creation; the endpoint takes no expiry parameter (same GH section). A longer task needs a refresh (#90). A token can be revoked early with `DELETE /installation/token`, authenticated with that token itself (GH "REST API endpoints for GitHub App installations", *Revoke an installation access token*), so the orchestrator can end it with the task.
- Token format: since 2026-04-27 GitHub is rolling out a stateless `ghs_APPID_JWT` format, longer than 40 characters (same GH section). Agent Vault's bearer value accepts up to 8192 characters (IS `agent-vault-credential-schemas.ts:76`), so this fits.

### Note for #90

Infisical's GitHub dynamic secret (IS `backend/src/ee/services/dynamic-secret/providers/github.ts:60`) posts to `/access_tokens` with no body, so the tokens it issues carry the installation's full repo set and every App permission. It cannot narrow per repository or per permission at `v0.167.6`, and Agent Vault cannot consume it directly anyway (above).

## Caveats

- Everything here is read from source and docs at the deployed tags; nothing was exercised against the cluster. The per-slot shape depends on a machine identity's personal values, which AGENTS.md says the API supports but the UI does not cover.
- The per-task-bundle shape gives the orchestrator Agent Vault Admin, which can also set delegations, read every session and change every service. It belongs only in a component that is itself outside the workspaces (for example whatever drives Coder in spec 013), never in a workspace.
- Revocation is not instant: up to one poll interval (60 s default), up to five during an Infisical outage. Revoking the installation token at GitHub at task end closes that window for the GitHub path.
- A session's TTL and the token's one-hour life are independent; a session that outlives its token keeps injecting a dead credential until something rewrites it.
