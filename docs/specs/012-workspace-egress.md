# Spec 012 — Workspace credentials and egress

**Status:** Draft (2026-11-11), waiting on #77 (image bakery)
**Related decisions:** [Decision 080](../../DECISIONS.md) — Agent Vault; egress NetworkPolicy deferred to the Coder work. [Decision 081](../../DECISIONS.md) — Coder as the workspace platform.
**Related specs:** [Spec 010](010-agent-vault-hermes.md) — Agent Vault proxy, session-as-Secret, header credentials. [Spec 011](011-coder-install.md) — Coder, the workspace template.
**Related issues:** #77 (workspace image from the external bakery), #79 (Hermes pod hardening).

---

## 1. Problem

Hermes will hand coding tasks to OpenCode running in Coder workspaces (specs 013, 014). A workspace runs code the agent wrote after reading untrusted issue text, so it must not hold real credentials and must not reach the internet except through a point that is logged and controlled. Today a workspace has open egress, no git credentials, no LLM, and no OpenCode.

This spec gives a workspace exactly what a coding task needs (an LLM through Aperture, git and pull requests on GitHub through Agent Vault, OpenCode itself), and closes every other path out.

## 2. Phases

| Spec    | Scope                                                                                                         |
| ------- | ------------------------------------------------------------------------------------------------------------- |
| **012** | Workspace egress: Aperture path, GitHub App credential brokered by Agent Vault, egress NetworkPolicy, OpenCode | this spec |
| 013     | Hermes drives Coder: Coder account and token, CLI in Hermes, create → detached `opencode run` → poll → PR → delete, triggered by hand for one issue | later |
| 014     | The issue loop: schedule, label trust check, claim and failure labels, overlap with the Claude routines        | later     |

## 3. Decisions within this spec

- **GitHub access through a GitHub App**, not a machine user. Repos are owned by a personal account, where a collaborator's token can't be scoped per repo or per permission; an App's installation tokens can. PRs are authored by `<app>[bot]`, so they can be reviewed and approved by the owner, and branch protection can require it.
- **App installation = the repos the agent may work on.** Overlap with the Claude routines is allowed (spec 014 defines how they keep apart). Every installed repo has a ruleset on its default branch: PR required, owner approval required, the App not in the bypass list.
- **Workspace token scope: `contents: write`, `pull_requests: write`** (plus implicit `metadata: read`), minted narrowed to those permissions across all installed repos. Narrowing to the task's one repo needs a per-task credential, which belongs to spec 013. Hermes's own token (issues, labels) is spec 014's.
- **Installation tokens expire after an hour, so a minter refreshes the Agent Vault credential.** A CronJob holds the App private key, mints a narrowed installation token every 30 minutes and writes it to the GitHub services of bundle `workspace`. Neither Hermes nor any workspace ever sees the private key or a real token. If Infisical can source the credential from a GitHub App dynamic secret, that replaces the minter (step 0).
- **Two GitHub services on bundle `workspace`:** `github.com` for git smart HTTP (header `Authorization: Basic base64("x-access-token:<token>")`) and `api.github.com` for `gh` and the REST API (`Authorization: Bearer <token>`). The proxy overwrites whatever header the client sends (verified for Tavily in spec 010), so clients get placeholders: `GH_TOKEN=agent-vault-github`, no git credential helper.
- **One session for all workspaces**, sealed as Secret `workspace-agent-vault` in `coder-workspaces`, read by the template into `HTTPS_PROXY`. Its token is visible to workspace code, but only works at the in-cluster proxy, only for bundle `workspace`, and the proxy only accepts traffic from `hermes` and `coder-workspaces`. Per-task sessions come with spec 013.
- **Traffic policy stays `any-host`** (the proxy is shared with Hermes). Workspaces need arbitrary package registries and release downloads; all of it is decrypted and logged at the proxy, credentials attach only to the GitHub services.
- **Aperture through a shared egress, not a tailnet node per workspace.** Deployment `aperture-egress` in its own namespace: a tailscale container (kernel mode, `--shields-up`, its own tag, state in a Secret, as Hermes's sidecar) and a small HTTP reverse proxy forwarding to `http://ai.taild13083.ts.net` (pinned `100.126.29.31`), setting the `Host` Aperture expects. ClusterIP Service `aperture.aperture-egress.svc:80`. No tailnet credential lands in a workspace. Aperture sees one identity for all workspaces; per-task attribution comes from Hermes's logs (spec 013).
- **Plain HTTP between workspace and egress.** Aperture itself is plain HTTP over the tailnet; the hop inside the cluster adds no TLS. Accepted: same trust domain as the rest of the cluster's internal HTTP.
- **Egress NetworkPolicy on `coder-workspaces`, default deny.** Allowed: kube-dns (53/UDP+TCP), coderd (agent and `coder ssh` relay via DERP over the access URL), `agent-vault-proxy:17323`, `aperture-egress:80`. Nothing else, so bypassing the proxy fails outright. The `agent-vault` ingress policy gains `coder-workspaces`.
- **The workspace trusts the Agent Vault CA.** The CA-bundle init container appends it; `SSL_CERT_FILE`, `CURL_CA_BUNDLE`, `GIT_SSL_CAINFO` point at the bundle, `NODE_EXTRA_CA_CERTS` at the extra CAs alone (as for Hermes). The CA PEM goes into the `homekube-ca` ConfigMap in `coder-workspaces` as a second key.
- **`NO_PROXY`** as for Hermes (`.svc`, `.cluster.local`, `localhost`, `127.0.0.1`, the cluster and LAN CIDRs) so coderd, Aperture egress and the proxy itself are direct. `.ts.net` is not needed: workspaces never resolve tailnet names.
- **OpenCode from the bakery image (#77)**, pinned with the existing `# renovate:` comment. Fallback if the image is not ready: the **stopgap**: the agent's `startup_script` downloads a pinned OpenCode `linux-arm64` release through the proxy into `~/.local/bin`, verifies its SHA-256 against a value in the template, and skips the download if that version is already there. The version and checksum carry a `# renovate:` comment. Removed when the bakery image ships OpenCode.
- **OpenCode configured by the template**, not by the user: a `~/.config/opencode/opencode.json` written by the startup script with one provider pointing at `http://aperture.aperture-egress.svc`, the model from template parameter `model` (default `qwen/qwen3.8-27b`, so spec 013 can choose per task), and permissions set to allow everything (the workspace is the sandbox; the boundaries are egress, the token scope and branch protection).

## 4. Current state (verified 2026-11-11)

- `coder-workspaces` has no NetworkPolicy; workspace egress is open.
- `agent-vault` ingress policy admits namespace `hermes` only, port 17323.
- Aperture: `http://ai.taild13083.ts.net`, `100.126.29.31`, authenticates by tailnet identity, holds the upstream LLM keys; Hermes uses a dummy `api_key` (spec 010 §3).
- Hermes reaches Aperture through a tailscale sidecar (`TS_HOSTNAME=hermes-aperture`, kernel mode, `--shields-up`, `TS_AUTHKEY` from a sealed secret, state in Secret `hermes-tailscale-state`). No Tailscale Kubernetes operator is installed.
- The Agent Vault proxy carries no WebSockets (spec 010 §9); a bearer credential overwrites the client's `Authorization` header.
- Workspace template: CA-bundle init container (system bundle + homekube-ca), `SSL_CERT_FILE`/`CURL_CA_BUNDLE`, no proxy env, image `codercom/example-base:ubuntu-20261105`.
- No GitHub App exists for homekube.
- Not verified yet, see step 0: OpenCode's proxy/CA behaviour and Aperture config, Agent Vault Basic-auth credentials and API updates, Cilium policy on the coderd LB IP.

## 5. Target state

### 5a. Human-created (README human steps)

- **Sandbox repo** `jangroth/agent-sandbox`: private, a trivial codebase, the only target in this spec.
- **GitHub App** `homekube-agent` on the personal account: no webhook; repository permissions `contents: write`, `pull_requests: write`, `issues: write` (for spec 014; the workspace token is minted without it), `metadata: read`. Installed with "Only select repositories" on `agent-sandbox`; real repos are added one at a time after spec 013. Private key in the password manager, sealed as Secret `github-app` (App ID, installation ID, key).
- **Rulesets** on each installed repo's default branch: PR required, approval required, no bypass for the App.
- **Tailscale auth key** for tag `tag:aperture-egress` (tbd), ACL grant to Aperture; sealed as `aperture-egress-tailscale`.
- **Agent Vault:** bundle `workspace` with services `github-git` (`github.com`) and `github-api` (`api.github.com`); a session on it, sealed into `coder-workspaces` as the proxy URL. A machine identity for the minter, if the minter writes through the Infisical API.

### 5b. `homekube-apps/applications/`

| Where | Content |
| ----- | ------- |
| `wave-03-apps/aperture-egress/` | Namespace, Deployment (tailscale + reverse proxy, data-plane, small requests), Service, sealed auth key, state Secret RBAC as for Hermes's sidecar, ingress NetworkPolicy admitting `coder-workspaces` only |
| `wave-03-apps/github-app-minter/` | CronJob (every 30 min, `concurrencyPolicy: Forbid`), sealed `github-app`, the minter's Infisical credential; no ingress |
| `wave-03-apps/agent-vault/networkpolicy.yaml` | ingress also from `coder-workspaces` |
| `wave-03-apps/coder-extras/` | `workspace-egress` NetworkPolicy; sealed `workspace-agent-vault`; `homekube-ca` ConfigMap in `coder-workspaces` gains `agent-vault-ca.crt` |
| `applications/kustomization.yaml` | the two new Applications |

### 5c. Template (`manual/coder-templates/kubernetes/main.tf`)

- Init container appends `agent-vault-ca.crt` to the bundle and writes the extra-CA file.
- Env: `HTTPS_PROXY`/`HTTP_PROXY` from Secret `workspace-agent-vault`, `NO_PROXY`, `GIT_SSL_CAINFO`, `NODE_EXTRA_CA_CERTS`, `GH_TOKEN=agent-vault-github`.
- `coder_parameter` `model`, default `qwen/qwen3.8-27b`, mutable.
- `coder_agent.startup_script`: install pinned OpenCode (checksum, idempotent), write `opencode.json`, git identity of the App's bot user.

### 5d. Renovate

Regex entries for the OpenCode version and checksum in the template, and for the images in `aperture-egress` and the minter.

## 6. Execution plan

0. **Verify:**
   - On darth: OpenCode against Aperture with `qwen/qwen3.8-27b` (provider type, base URL, model id, whether a dummy key is needed; tool calling works), and `opencode run "<task>"` completes non-interactively with a meaningful exit code. Record its arm64 release asset and checksum.
   - In a throwaway pod in `coder-workspaces`: OpenCode (Bun) and git honour `HTTPS_PROXY` and the bundle env vars; which downloads OpenCode makes at start (models list, LSP servers).
   - Agent Vault: a Basic `Authorization` header credential works for git smart HTTP; a service credential can be updated through the Infisical API by a machine identity, or sourced from an Infisical GitHub App dynamic secret with narrowed permissions; the proxy passes `git push` (chunked POST) intact.
   - GitHub: installation token minted with narrowed `permissions` is refused for issues; ruleset blocks the App from pushing to the default branch.
   - Cilium: an egress policy allowing coderd pods by namespace also allows traffic to the LB IP `192.168.86.248` (service translation before policy); the agent stays connected with STUN blocked.
   - Aperture accepts requests through the egress with the rewritten `Host`, and with the egress node's identity.
1. Create `agent-sandbox`, the GitHub App, rulesets, Tailscale key and ACL, Agent Vault bundle and session; store in the password manager; seal. _(human step)_
2. PR to `homekube-apps`: 5b without the `workspace-egress` policy. Check: egress pod on the tailnet, `curl aperture.aperture-egress.svc` from a workspace reaches Aperture; minter run updates the credential (Loki); a `git ls-remote` of `agent-sandbox` through the proxy shows `brokered`.
3. PR to `homekube-apps`: 5c and 5d. Push the template, update a workspace. Check: OpenCode installed, `opencode run` answers through Aperture, `git clone`/`push` to a branch and `gh pr create` work in an installed repo; the PR is authored by the App.
4. PR to `homekube-apps`: the `workspace-egress` policy. Check: everything in step 3 still works; `curl https://example.com --noproxy '*'` and a direct `git clone` fail; DNS works; web terminal and `coder ssh` work.
5. Negative checks: push to the default branch refused; a token-less request to a non-installed private repo fails; a session revoked in Infisical cuts the workspace off from GitHub within a poll interval; the private key and real tokens appear in no workspace env, file or log.
6. README human steps (App, key rotation, Tailscale key, session rotation); CHANGELOG; decision entry; spec Done.

## 7. Acceptance criteria

- [ ] A workspace reaches Aperture, the Agent Vault proxy, coderd and DNS, and nothing else
- [ ] OpenCode runs in a workspace from the pinned, checksum-verified release and answers through Aperture non-interactively
- [ ] `git clone`, `git push` to a branch and `gh pr create` work in an installed repo; the PR is authored by the App
- [ ] The App's token never appears in a workspace; the proxy log shows `brokered` for the GitHub services
- [ ] The token is refreshed before expiry with no workspace change; a minter failure shows up (Loki, failed Job)
- [ ] The App can't push to a default branch or merge
- [ ] Web terminal and `coder ssh` work with the egress policy in place
- [ ] No tailnet credential in `coder-workspaces`

## 8. Open questions

1. ~~**App name and installed repos.**~~ Resolved: `homekube-agent`, installed on `jangroth/agent-sandbox` only (5a).
2. ~~**Model.**~~ Resolved: `qwen/qwen3.8-27b` as the default of template parameter `model`, not fixed (§3).
3. **Minter vs dynamic secret.** Step 0 decides: the dynamic secret if Infisical supports GitHub App tokens, narrowed permissions, and Agent Vault can use one as a service credential; otherwise the minter.

## 9. Risks

- **Shared credential across workspaces.** Any workspace can push branches and open PRs in every installed repo until spec 013 narrows tokens per task. Rulesets bound the damage to branches and PRs.
- **Session token readable by workspace code.** Usable only at the proxy, from `hermes` and `coder-workspaces`, for bundle `workspace`; revocable.
- **Minter as a new failure point.** If it stops, git fails within an hour; alerting on failed Jobs covers it.
- **Proxy decrypts everything a workspace sends**, including source code pushed to GitHub. Same trust model as Hermes.
- **Per-start download of OpenCode** until #77; it fails when GitHub release downloads do (see spec 011, 504s). Cached in home, so only the first start of a workspace pays.
- **Aperture sees one identity** for all workspaces; quotas or limits there apply to all of them together.
- **`terraform init` and the agent download still need coderd's internet access**; unaffected, coderd isn't in `coder-workspaces`.

## 10. Rollback

Remove the `workspace-egress` policy first (restores open egress), then template changes (push the previous version), then the `aperture-egress` and minter Applications. Revoke the session and delete bundle `workspace` in Infisical; uninstall the GitHub App and revoke its key; remove the Tailscale node and key.

## 11. Out of scope

Hermes driving Coder and per-task credentials (spec 013), the issue loop and Hermes's GitHub token (spec 014), the workspace image (#77), Hermes pod hardening (#79), a Terraform provider mirror, egress policy for `hermes` itself.
