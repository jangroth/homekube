# Research: headless workspace lifecycle through Coder

Resolves #101 (Research: headless workspace lifecycle through Coder), part of the map #100 (agents coding via Coder workspaces).

**Question.** Can Coder's CLI or API, with one service token, create a workspace from the template with parameters, run `opencode run` detached inside it, poll it to completion, and delete the workspace? Which token types and lifetimes does Coder offer for a non-human account?

**Version.** homekube pins the Coder Helm chart at `2.39.0` (`homekube-apps/applications/wave-03-apps/coder.yaml`), running the OSS edition with no license. All sources below are the `coder/coder` repo at tag `v2.39.0` (commit `8d897357`, tagged 2026-11-03), docs included (`docs/` in that tree is what coder.com/docs renders for that release).

## Answer

**Yes for the lifecycle, with one caveat on the account.** One API token lets Hermes do create, exec, poll and delete through the plain `coder` CLI. "Detached" is not a Coder feature, though: Hermes backgrounds the process itself inside a `coder ssh` command. **Service accounts are Premium-only in v2.39**, and OSS no longer lets you create a headless (`login_type: none`) user. On OSS the non-human account has to be an ordinary member user whose interactive login is never used, holding a long-lived API token that an Owner mints for it.

## 1. Lifecycle, step by step

The CLI reads `CODER_URL` and `CODER_SESSION_TOKEN` from the environment (`cli/root.go`, `envURL`/`envSessionToken`), so a token in Hermes' environment is enough: no `coder login` and no state on disk.

| Step | CLI | REST equivalent |
|------|-----|-----------------|
| Create from template, with parameters | `coder create <name> -t kubernetes --parameter memory=2Gi -y` (or `--rich-parameter-file`, `--use-parameter-defaults`; `--no-wait` to return before the build finishes) | `POST /api/v2/users/{user}/workspaces` (or `/organizations/{org}/members/{user}/workspaces`) with `template_id` and `rich_parameter_values` |
| Run OpenCode | `coder ssh <name> --wait=yes -- sh -c '…'` | none in REST; see §2 |
| Poll | `coder ssh <name> -- test -f …` / `cat …`; `coder list -o json`, `coder show` for workspace state | `GET /api/v2/users/{user}/workspace/{name}` |
| Delete | `coder delete <name> -y` | `POST /api/v2/workspaces/{id}/builds` with `"transition": "delete"` |

Sources: `docs/reference/cli/create.md`, `delete.md`, `ssh.md`; `docs/reference/api/workspaces.md`, `builds.md`.

Notes on the homekube template (`homekube-apps/manual/coder-templates/kubernetes/main.tf`):

- Its only parameter is `memory` (mutable, default `1Gi`, options `1Gi`/`2Gi`). A non-interactive `coder create` should pass `--parameter` or `--use-parameter-defaults` so that it never stops at a prompt.
- Delete tears down the pod and the home PVC (`kubernetes_persistent_volume_claim_v1.home` has no `count`, so it lives as long as the workspace), so nothing is left behind after delete.
- `coder create` without `--no-wait` blocks until the build finishes. `coder ssh --wait=yes` then waits for the agent's startup scripts. Between them they cover "workspace ready" without a separate poll.

## 2. Running `opencode run` detached

`coder ssh <ws> [command]` runs a command without a PTY over Coder's tailnet: no SSH keys and no `config-ssh`, just the token. How the v2.39 agent treats such a command (`agent/agentssh/agentssh.go`, `startNonPTYSession`):

- The command starts in its own session (`Setsid: true`, `agent/agentssh/exec_other.go`).
- `cmd.Cancel = nil`: "to match OpenSSH, we don't actually tear a non-TTY command down, even if the session ends". When the session closes, only its stdio pipes close.
- The agent sends SIGHUP to the process group only when the agent itself shuts down (`cmdCancel`), which happens when the workspace stops or is deleted.

So a pattern like this outlives the `coder ssh` call that started it:

```sh
coder ssh "$WS" --wait=yes -- sh -c \
  'cd ~/repo && nohup sh -c "opencode run \"$PROMPT\"; echo \$? > ~/.task/exit" > ~/.task/log 2>&1 < /dev/null &'
```

The output must be redirected, because once the session ends a write to its closed stdout would hit SIGPIPE. Hermes then polls with short `coder ssh "$WS" -- cat ~/.task/exit` calls: a missing file means the task is still running, and the file's content is OpenCode's exit code. Holding one long `coder ssh` open instead also works, but a Hermes restart would cut it.

Other routes looked at and not recommended:

- **Agent process API.** The v2.39 agent serves `/api/v0/processes` (`start`, `list`, `{id}/output`, `{id}/signal`; `agent/agentproc/api.go`). It is reachable only by dialling the agent over tailnet through the Go SDK, and no CLI command or public REST route exposes it. It is an internal surface (it serves Coder Agents), not a stable contract.
- **Coder Tasks.** Deprecated in v2.34 and removed, `/api/v2/tasks` included (`docs/ai-coder/agents/tasks-to-chats-migration.md`). The replacement, Chats / Coder Agents, runs the agent loop in the control plane, not OpenCode in the workspace, so it does not fit this design.
- **Prompt as a template parameter run by a `coder_script`.** This would work, but it changes the template and puts the prompt into build parameters. `coder ssh` keeps the template generic.

## 3. Token types

From `docs/admin/users/sessions-tokens.md` and `docs/reference/cli/server/index.md`:

| Type | How it is obtained | Lifetime |
|------|--------------------|----------|
| Session token | browser login or `coder login` (`/cli-auth`) | `--session-duration`, default **24h**, refreshed while in use unless `--disable-session-expiry-refresh` |
| API token ("long-lived") | `coder tokens create` / `POST /api/v2/users/{user}/keys/tokens` | `--lifetime` up to the server cap; with no lifetime set it gets `--default-token-lifetime`, default **168h** |

How the server caps lifetime (`coderd/apikey.go`, `getMaxTokenLifetime`): the cap depends on the roles of the user who **owns** the token, not of the caller.

- `--max-token-lifetime` (`CODER_MAX_TOKEN_LIFETIME`), default **876600h (~100 years)**, applies to non-Owner users.
- `--max-admin-token-lifetime` (`CODER_MAX_ADMIN_TOKEN_LIFETIME`), default **168h (7 days)**, applies to users with the Owner role.

homekube sets neither (they are not in the Helm values; `coder-secrets` is unverified), so the defaults apply. A non-Owner Hermes user can therefore hold a token of a year or more, while an Owner account would be capped at 7 days. That is one more reason not to run Hermes as an Owner.

**Scopes and allow lists** (OSS, enforced in `coderd`): `--scope` and `--allow <type>:<uuid>` narrow a token (`docs/reference/api-key-scopes.md`). Composite scopes that fit the lifecycle are `coder:workspaces.create`, `coder:workspaces.access` (it carries `workspace:ssh`) and `coder:workspaces.delete`. A token minted *with* a scoped token cannot exceed that token's scopes, and its expiry is clamped to that token's expiry (`coderd/apikey/apikey.go`, `InheritWithinCaller`). A token minted with an unscoped (`coder:all`) session is not clamped. A workspace allow list is no use here, because the workspace UUID does not exist until Hermes creates it.

**Minting for another user:** `coder tokens create --user <name> --lifetime <d> --name <n>` (v2.17+) requires the Owner role (`sessions-tokens.md`). Revocation is `coder tokens remove` (soft, expires the token) or `--delete` (hard). Deleting the user revokes all of that user's tokens.

## 4. Non-human accounts and OSS licensing

- `docs/admin/users/headless-auth.md`: "Creating service accounts requires a Premium license." The server enforces this. `POST /users` with `service_account: true` returns 403 unless the `service_accounts` feature is entitled (`coderd/users.go`; `codersdk/deployment.go` lists it among the licensed features).
- The old OSS workaround is gone in v2.39. `--login-type none` and `--disable-login` are rejected by the CLI as deprecated (`cli/usercreate.go`), and the server rejects `login_type: none` without `service_account: true` ("Login type 'none' requires a service account.", `coderd/users.go`).
- What OSS offers instead is an ordinary user with `--login-type password` or `oidc`, role `member`, and an Owner-minted API token. This has three side effects:
  - The account has a login method in principle. With `password`, it gets a random password that nobody keeps; password auth stays enabled on homekube because `CODER_DISABLE_PASSWORD_AUTH` is not set. With `oidc`, it can only log in if Dex ever holds a matching identity, and Dex signups are off (`CODER_OIDC_ALLOW_SIGNUPS=false`).
  - It is a normal user and shows in user listings. Dormancy is not a risk: the 90-day dormant-user job lives in `enterprise/coderd/dormancy`, so it does not run on OSS, and every request made with the token updates `last_seen_at` anyway (`coderd/httpmw/apikey.go`).
  - Rotation is manual: an Owner mints a new token before expiry, or Hermes mints its own successor using its own unscoped token.
- No other OSS limit stands in the way: token creation, scopes, minting for another user, `coder create/ssh/delete` are all AGPL `coderd`/`cli` code.

## Caveats

- Nothing here was run against the cluster (agents have no cluster access, ADR-0009). The exact minimal scope set for the CLI path (for example whether `coder ssh`'s tailnet coordination or `coder create`'s template lookup needs anything beyond the three composite scopes) is unverified. Before narrowing, a human should try it with an unscoped token first.
- Workspace autostop: templates default to `--default-ttl 24h` (`cli/templatecreate.go`). A detached run with no open session may not bump activity, so a long task must fit the template's TTL, or the TTL must be set explicitly. Hermes deleting the workspace when the task ends makes this moot for normal runs.
- `--parameter` changes to `memory` after creation go through `coder update`; it is mutable, but not needed for a one-shot task.
