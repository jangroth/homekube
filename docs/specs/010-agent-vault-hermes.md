# Spec 010 — Infisical Agent Vault for Hermes

**Status:** Draft (2026-11-04)
**Related decisions:** [Decision 080](../../DECISIONS.md) — Agent Vault for Hermes, Infisical operator instead of ESO; reorders the phases of [decision 079](../../DECISIONS.md). [Decision 075](../../DECISIONS.md) — Hermes image pins.
**Related specs:** [Spec 009](009-infisical-phase-1.md) — Infisical install. [herminator spec 001](https://github.com/jangroth/herminator/blob/main/docs/specs/001-deploy-hermes-to-homekube.md) — Hermes deployment.

---

## 1. Problem

Hermes runs code, browses and calls tools, so anything in its environment can leak through a log line, a message or a prompt injection. Today its outbound API credentials sit in plaintext in `/opt/data/.env` on its PVC: `TAVILY_API_KEY` and `TELEGRAM_BOT_TOKEN`. They were entered through Hermes itself, so they are in no source file and can't be rotated or revoked centrally.

Infisical Agent Vault is a forward proxy that attaches real credentials to an agent's outbound HTTPS requests, so the agent only holds a revocable, time-bound session token that is useless anywhere but at the proxy. Proving it with Hermes is the groundwork for Coder workspaces, the use case decision 079 was adopted for.

## 2. Phases (decision 079, reordered)

| Phase | Scope | Spec |
|---|---|---|
| 1 | Infisical install | [009](009-infisical-phase-1.md), done |
| **2** | Agent Vault proxy in-cluster; Hermes's Tavily key brokered | this spec |
| 3 | Infisical operator (Kubernetes Auth, auth per namespace, one project with a folder per app), one test secret | later |
| 4 | Migrate app secrets, `pg_dump` backup | later |
| 5 | Ansible + Terraform on darth read from Infisical | later |

Coder workspaces on Agent Vault are a separate spec once phase 2 is proven.

## 3. Hermes today (verified 2026-11-04)

| Credential | Where | Used for | Brokerable? |
|---|---|---|---|
| `TAVILY_API_KEY` | `/opt/data/.env` (PVC) | Tavily web search, HTTPS | Yes: **pilot** |
| `TELEGRAM_BOT_TOKEN` | `/opt/data/.env` (PVC) | Telegram Bot API, HTTPS; token is in the URL path | Yes, via path substitution (§12) |
| Aperture `api_key` | `/opt/data/config.yaml` | LLM calls via `http://ai.taild13083.ts.net` over the tailscale sidecar | Not a credential: dummy value, Aperture authenticates by tailnet identity and holds the upstream LLM keys |
| `nous` OAuth tokens | `/opt/data/auth.json` | Nous provider | No: refreshing OAuth tokens |
| `API_SERVER_KEY` | sealed secret `hermes-secrets` | inbound auth to Hermes's API | No: inbound |
| `TS_AUTHKEY` | sealed secret `hermes-secrets` | tailscale sidecar | No: not HTTP |
| `STATE_EXPORT_SSH_KEY` | sealed secret `hermes-secrets` | state-export sidecar, git over SSH | No: SSH, other container |

- Hermes is Python; `SSL_CERT_FILE` and `REQUESTS_CA_BUNDLE` already point at a combined bundle built by the `build-ca-bundle` init container (system store + the chart's `caCert` value); `NODE_EXTRA_CA_CERTS` points at `caCert` alone.
- Dex is reached as `https://pi0.taild13083.ts.net/dex`, Aperture as `http://ai.taild13083.ts.net`; both by hostname.
- No `HTTPS_PROXY` is set. The herminator chart has no proxy settings and no NetworkPolicy template.
- The tailscale sidecar runs in kernel mode (`TS_USERSPACE=false`) in the pod's network namespace; Aperture resolves through a `hostAliases` pin to `100.126.29.31`. The sidecar also routes the `192.168.86.240/28` VIPs over the tailnet.
- Agent Vault is present in Infisical `v0.167.0` (`backend/src/ee/services/agent-vault*`). The on-prem default features only disable session-log storage options; no licence check gates the proxy or sessions.
- `infisical/cli` images are published for `arm64`.

## 4. Decisions within this spec

- **Pilot one credential: Tavily.** It is a plain header-authenticated HTTPS API that Hermes uses regularly, so success and failure are easy to see. Telegram follows in step 9.
- **One shared proxy, its own namespace.** Deployment `agent-vault-proxy` in namespace `agent-vault`, `infisical/cli` running `infisical agent-vault proxy`, ClusterIP Service. Running it outside the Hermes pod keeps the proxy token and the proxy CA's private key out of the agent's reach (Agent Vault docs). The same proxy later serves Coder workspaces.
- **Proxy talks to Infisical in-cluster** at `http://infisical.infisical.svc:8080/api` (`INFISICAL_DOMAIN`), bypassing the TLS sidecar. Traffic stays inside the cluster.
- **Proxy token via sealed secret.** It is bootstrap-tier, like Infisical's own keys (decision 079).
- **Traffic policy `any-host`.** `HTTPS_PROXY` routes all of Hermes's HTTPS through the proxy, and Hermes browses arbitrary sites. The proxy decrypts every HTTPS host under either policy; `bundle-hosts` additionally refuses hosts no service covers, which would break general browsing. Credentials are only attached for the Tavily service.
- **`NO_PROXY`** for cluster and tailnet destinations: `.svc`, `.cluster.local`, `.ts.net`, `10.0.0.0/8`, `100.64.0.0/10`, `192.168.86.0/24`, `localhost`, `127.0.0.1`, plus `api.telegram.org` until step 9. httpx and urllib ignore the CIDR entries (only `requests` matches them), so the hostname entries carry Aperture and Dex; anything Hermes reaches by IP is checked in step 6.
- **Telegram bypasses the proxy until it is brokered.** Its bot token is in the URL path, and the proxy would decrypt it. Step 9 brokers it with a path substitution; the proxy logs the agent's pre-substitution path, so the real token never reaches a log.
- **Session token delivered as a Secret, not minted in the pod.** Running `infisical agent-vault run` inside the Hermes container would put a machine identity in the agent's environment, which can mint sessions. Instead the session is created in the Infisical UI and the full proxy URL (`http://x-agent-vault:<session-token>@agent-vault-proxy.agent-vault.svc:17323`; the token is the password, the username is fixed) is sealed into the `hermes` namespace and injected as `HTTPS_PROXY`. The token is still static in the pod, but it is scoped to one bundle, only works at the proxy, and is revocable in one click.
- **Session TTL `never`, revoked by hand.** A fixed TTL would force a reseal and Hermes restart on every expiry, for a token that only works at an in-cluster proxy and for one bundle. Rotating the brokered credentials themselves happens in Infisical and doesn't touch Hermes. Short-lived, automatically minted sessions belong with the Coder work.
- **Session rotation is make-before-break.** A revoked token is presumably rejected for every request the proxy handles, cutting off all proxied web access, not just search. Rotation creates the new session, reseals, restarts Hermes, then revokes the old session. Revoking first is the incident path.
- **Hermes trusts the proxy CA through chart value `agentVault.caCert`**, appended by `build-ca-bundle` to the combined bundle and to the `NODE_EXTRA_CA_CERTS` file; `CURL_CA_BUNDLE` points at the combined bundle too, since curl honours `HTTPS_PROXY` but not `SSL_CERT_FILE`. It is set in homekube-apps, not in the chart's defaults, so a CA change is one homekube-apps PR. The CA is public: Infisical issues it, the proxy serves it at `GET /_agent-vault/ca`, and it changes only when the proxy is re-enrolled with a new proxy token. The endpoint is unauthenticated plain HTTP, so the PEM is fetched through `kubectl port-forward` and its SHA-256 fingerprint (`openssl x509 -noout -fingerprint -sha256`) is compared with the one on the Proxies page before it goes into `agentVault.caCert`. The proxy's data dir is a fallback cache, so `emptyDir` is enough.
- **`TAVILY_API_KEY` becomes a placeholder** (`agent-vault-tavily`; Hermes treats `dummy`, `placeholder`, `changeme`, `none` and all-`x` values as unset) in `/opt/data/.env`, so Hermes still enables the tool; a bearer credential on the Tavily service overwrites the `Authorization` header the plugin sends. Hermes's ad-hoc scripts in `/opt/data/briefing/`, which read the key from `.env` and send it in the request body, are left to break. The real key moves to the access bundle and is removed from the PVC. The key is rotated at Tavily afterwards, since it has sat in plaintext on the PVC and its backups, and probably in Hermes's conversation history and state export, since it was entered through Hermes.
- **Ingress NetworkPolicy on `agent-vault`, no egress policy on Hermes.** The proxy accepts traffic from namespace `hermes` only, so a leaked session token can't be used from other pods. Egress isn't restricted: the real credential is no longer in the pod, so bypassing the proxy only means sending requests without it. Locking egress down needs allow-rules for the tailscale sidecar's WireGuard/DERP traffic and belongs with the Coder work, where untrusted code makes it essential.
- **Chart changes land in herminator** as one optional `agentVault` block ([herminator change `agent-vault-proxy`](https://github.com/jangroth/herminator/tree/main/openspec/changes/agent-vault-proxy)): `encryptedHttpsProxy` (ciphertext; the chart renders SealedSecret `hermes-agent-vault`), `caCert` and `noProxy`, off by default. Only the `hermes` container gets `HTTPS_PROXY`, `NO_PROXY` and `CURL_CA_BUNDLE`, and a checksum annotation restarts Hermes when the ciphertext or CA changes. homekube-apps only sets values.

## 5. Target state

### 5a. `homekube-apps/applications/wave-03-apps/agent-vault.yaml`

Plain manifests (no chart exists), via an ArgoCD `Application` pointing at `applications/wave-03-apps/agent-vault/`, sync wave `3`, `CreateNamespace=true`. Added to `applications/kustomization.yaml`.

| File | Content |
|---|---|
| `deployment.yaml` | 1 replica, `infisical/cli:<pinned>` (Renovate-tracked), args `agent-vault proxy --data-dir /data --log-format json`; env `INFISICAL_DOMAIN`, `INFISICAL_DISABLE_TELEMETRY=1`, `INFISICAL_AGENT_VAULT_PROXY_TOKEN` from `agent-vault-proxy-token`; `/data` on `emptyDir`; readiness `httpGet /_agent-vault/ca`, liveness TCP `17323`; resources `32Mi` / `10m` → `128Mi` / `200m` (initial guess, check in step 6); data-plane node affinity; `runAsUser: 65532`, read-only root filesystem |
| `service.yaml` | ClusterIP `agent-vault-proxy`, port `17323` |
| `networkpolicy.yaml` | Ingress to `agent-vault-proxy` from namespace `hermes` on the proxy port only |
| `proxy-token-sealedsecret.yaml` | Secret `agent-vault-proxy-token` |

### 5b. Infisical (UI, human step)

- The default Agent Vault project (the open-source edition can't create others); proxy `homekube` with traffic policy `any-host` and the default poll interval (60s)
- Service `tavily`: host `api.tavily.com`, bearer credential (`Authorization`, prefix `Bearer`) holding the real key, methods/paths limited to what Hermes calls (`POST /search`, `POST /extract`)
- Access bundle `hermes` containing `tavily`
- Session on bundle `hermes`, label `hermes`, TTL `never`

### 5c. Hermes

- herminator chart 0.1.14: optional `agentVault` block, off by default, with `chart/tests/agent-vault-render.sh` checking the chart renders unchanged without it; released by merging to herminator `main`, which the `hermes` Application tracks at `HEAD`
- homekube-apps `wave-03-apps/hermes.yaml` values: `agentVault.encryptedHttpsProxy` (key `HTTPS_PROXY` of `hermes-agent-vault`, sealed for namespace `hermes`) and `agentVault.caCert`; `noProxy` uses the chart defaults
- `/opt/data/.env`: `TAVILY_API_KEY=agent-vault-tavily`

## 6. Execution plan

0. **Verify:** done, findings in §12.
1. In Infisical: in the default project, create the proxy, service, bundle and session (5b); this also confirms Agent Vault works on unlicensed self-hosted. Store the proxy token and session token in the password manager. *(human step)*
2. Seal `agent-vault-proxy-token` (namespace `agent-vault`) and `hermes-agent-vault` (namespace `hermes`). *(human step)*
3. PR to `homekube-apps`: 5a. Merge, sync, check the proxy shows as connected in the Infisical UI.
4. PR to herminator: chart changes (5c). PR to `homekube-apps`: Hermes values, with the CA fetched via port-forward and its fingerprint checked against the Proxies page (§4). Merge herminator first.
5. Set `TAVILY_API_KEY=agent-vault-tavily` in `/opt/data/.env`, restart Hermes. Ask Hermes for a web search. *(human step)*
6. Check: the proxy log in Loki shows a `brokered` request for service `tavily`; a non-Tavily HTTPS fetch works; Aperture and Dex calls still work (bypass); Telegram still works and no `api.telegram.org` line is in the proxy log; nothing Hermes reaches by IP fails on the proxy; a pod outside `hermes` can't connect to the proxy; proxy memory use.
7. Rotation: create a new session, reseal `hermes-agent-vault`, restart Hermes, then revoke the old session; check searches keep working. Then revoke the new session and check all proxied web access gets `403` within one poll interval; create another session and reseal to recover. This is the rotation runbook. A CA change (proxy re-enrolment) repeats the fingerprint-checked fetch from step 4.
8. Rotate the Tavily key at Tavily, update the service in Infisical. If Hermes saw a 401 in between, it has marked the key exhausted: `hermes auth reset <provider>` and restart. *(human step)*
9. Telegram: add a `telegram` service to the bundle (host `api.telegram.org`, path substitution of a placeholder bot token), set the placeholder as `TELEGRAM_BOT_TOKEN`, drop `api.telegram.org` from `NO_PROXY`, repeat 5–6. The gateway exits instead of retrying when Telegram rejects its token, so a placeholder mismatch shows as a restarting pod.
10. CHANGELOG entry; amend decision 080 with anything else that differs; set this spec to Done.

## 7. Acceptance criteria

- [x] `agent-vault-proxy` Ready on arm64, connected to Infisical, reachable only from namespace `hermes`
- [ ] No real Tavily key in the Hermes pod's env, `/opt/data/.env` or `config.yaml`; the key Hermes held before is rotated, covering copies in its history, state export and backups
- [x] Hermes web search works; the proxy log shows the request as `brokered` for service `tavily`
- [ ] Revoking the session stops credential injection within one poll interval
- [ ] Hermes's general web access, Aperture LLM calls and Dex login unaffected
- [ ] No proxy log line contains the real Telegram token
- [ ] Proxy token and session token in the password manager
- [ ] Rotation runbook (new session → reseal → restart → revoke old; CA change → fingerprint-checked `agentVault.caCert` in homekube-apps; `hermes auth reset` after an upstream 401) in the homekube-apps README

## 8. Risks

- **Licensing.** Agent Vault lives in Infisical's `ee/` directory, which the repo describes as "premium enterprise features requiring a Infisical license", yet nothing in `v0.167.0` gates it. Fine for a study cluster; recorded in the decision entry.
- **Young feature.** Agent Vault has had roughly one DB migration a week since 2026-09. Infisical bumps are already backed up before merge (spec 009).
- **No WebSockets.** The proxy doesn't carry them; Telegram long-polls over HTTP and Aperture bypasses the proxy, but a WebSocket-based platform or tool would break.
- **Proxy as a single point of failure** for Hermes's brokered calls. Unbrokered HTTPS also flows through it, so a proxy outage breaks Hermes's web access too.
- **Infisical as a dependency of Hermes's web access.** The proxy validates sessions and fetches credentials from Infisical. Cached sessions survive an Infisical or Postgres outage for 5 × poll interval (5 min), then all proxied requests fail; a fresh proxy pod doesn't start without Infisical.
- **Decryption.** Every HTTPS request from Hermes outside `NO_PROXY` is decrypted by the proxy. Brokered and blocked requests are logged with method, host and path; passthrough only at `debug`, which must stay off.
- **No session logs.** Session-log ingest needs a paid plan, so there is no per-session audit trail in Infisical; the proxy's stdout in Loki is the only request record.

## 9. Open questions for Jan

1. ~~**Tavily auth placement.**~~ Resolved 2026-11-05: the plugin sends `Authorization: Bearer`; a bearer credential covers it (§12).
2. ~~**Telegram.**~~ Resolved 2026-11-05: path substitution covers `/bot<token>/…` (§12).
3. ~~**Session TTL.**~~ Resolved 2026-11-05: `never`, revoked by hand (§4).
4. ~~**Aperture `api_key` in git.**~~ Resolved 2026-11-05: a dummy value; Aperture authenticates by tailnet identity.

## 10. Rollback

Remove the `agentVault` block from the Hermes values, put the real Tavily key back into `/opt/data/.env`, restart Hermes. Delete the `agent-vault` Application (finalizer removes the namespace contents), then the namespace. Delete the project in Infisical.

## 11. Out of scope

Coder workspaces, egress NetworkPolicy, automated session minting, the Infisical operator, brokering non-HTTP credentials, moving `API_SERVER_KEY`/`TS_AUTHKEY`/state-export key out of sealed-secrets.

## 12. Step 0 findings (2026-11-05)

From `infisical/cli` `0.44.15` (source tag `v0.44.15`, `packages/agentvault/`), Infisical backend `v0.167.0` (bootstrap flow checked against `v0.167.6`), and the running `hermes-agent:v0.22.2` image. Cross-checked against Infisical's [Hermes gateway guide](https://infisical.com/docs/documentation/platform/agent-vault/guides/hermes-gateway). UI-side checks (proxy creation on unlicensed self-hosted) happen in step 1.

### Proxy

The proxy-token flow below needs Infisical `>= v0.167.2` and CLI `>= 0.44.7`; older pairs use a one-time enrollment token and a proxy-generated CA. Infisical was bumped to `v0.167.6` for this.


| Item | Finding |
|---|---|
| Image | `infisical/cli:0.44.15`, multi-arch incl. `arm64`; entrypoint `tini -- infisical`, no `USER` (root by default) |
| Command | `agent-vault proxy`; token from env `INFISICAL_AGENT_VAULT_PROXY_TOKEN` (not `--proxy-token`, which shows in the process list) |
| Port | `17323` (`--port`); SOCKS5 off by default |
| `INFISICAL_DOMAIN` | needs the `/api` suffix: `http://infisical.infisical.svc:8080/api` |
| Health | no health endpoint. `GET /_agent-vault/ca` (origin-form, unauthenticated) returns JSON with the CA PEM and fingerprint once the proxy serves: readiness probe. TCP on `17323` for liveness |
| Non-root, read-only rootfs | runs as `65532` with `--read-only`; only `--data-dir` must be writable (created `0700`). No `HOME` needed |
| Data dir | default `/etc/infisical/agent-vault`; holds settings + CA, read only when Infisical is unreachable at start. `emptyDir` is enough: it survives container restarts, and a fresh pod with Infisical down exits with `can't reach Infisical … not serving` after ~1 min of retries |
| CA | issued by Infisical, loaded at every start. Rotates when the proxy is re-enrolled (new proxy token); otherwise stable. Own CA possible via `--ca-cert`/`--ca-key` |
| Infisical down | cached sessions keep serving for 5 × poll interval (5 min at the default), then dropped; unresolvable sessions get `502 failed to resolve the session` |
| Poll interval | default `60`s, set on the proxy in Infisical |
| Proxy token revoked | `503 this proxy's access has been revoked` |
| Session revoked/expired | `403 the session is no longer valid` |
| Proxy URL | session token is the **password**: `http://x-agent-vault:<session-token>@agent-vault-proxy.agent-vault.svc:17323`. The username is fixed and ignored |
| Plain `http://` | forwarded in absolute form; `https://` only via `CONNECT` |
| Private destinations | refused only on the SOCKS5 door; the HTTP proxy reaches anything |

### Traffic policy

Values are `any-host` and `bundle-hosts`. **Every HTTPS host is intercepted (decrypted) under either policy**; there is no `CONNECT` passthrough. `bundle-hosts` refuses hosts no service covers (`403 no service covers host`), which would break Hermes's general browsing. So: **`any-host`**, as decision 080 already states. Under it, `api.telegram.org` must be in `NO_PROXY` until step 9 if its token is to stay out of the proxy.

### Credentials and substitutions

- Credential types: **bearer** (header name, default `Authorization`, optional prefix such as `Bearer`; `Header.Set`, so it overwrites what the agent sent), **basic**, **passthrough**. Plus custom headers.
- Substitutions: a placeholder (1–255 chars, no `{{`/`}}`) replaced on any of **path, query, header, body**. Body: skipped (placeholder goes upstream) on `Content-Encoding` or over the size limit.
- §9 Q1: built-in Tavily plugin (`/opt/hermes/plugins/web/tavily/provider.py`) sends `Authorization: Bearer <key>` via `httpx.post`. A bearer credential covers it. Separately, Hermes wrote four ad-hoc scripts on 2026-08-22 (`/opt/data/briefing/search_tavily*.py`) that read `TAVILY_API_KEY` from `/opt/data/.env` and send it as `api_key` in the JSON body via urllib. They stop working with the placeholder; accepted, the built-in plugin covers search.
- §9 Q2: **yes**, path substitution covers Telegram's `/bot<token>/…`. The logged path is the agent's (pre-substitution), so the real token never reaches a log.

### Session logs

**Not available**: ingest needs the `agentVaultByoS3` plan feature, so unlicensed self-hosted resolves to `unlicensed` and records nothing. Substitute: the proxy's stdout. Each request logs `method`, `host`, `path` (agent's), `decision`, `status`, `service`, `accessBundle`, `substituted`; **brokered at info, blocked at warn, errors at error, passthrough only at debug**. At the default level only brokered/blocked/failed requests show up, which goes to Loki. Never log level `debug`: passthrough paths would be logged in clear.

### Hermes clients

| Client | Proxy behaviour |
|---|---|
| Tavily plugin, `httpx 0.28.1` module-level calls | `trust_env` default on: honours `HTTPS_PROXY`/`NO_PROXY`; suffix entries (`.ts.net`) match, CIDRs don't |
| Telegram (`python-telegram-bot 22.8`) | Hermes passes `proxy=` from `resolve_proxy_url("TELEGRAM_PROXY", target_hosts=["api.telegram.org"])`: `TELEGRAM_PROXY` → `telegram.proxy_url` → `HTTPS_PROXY` (when `gateway.trust_env`, default true, unset in `config.yaml`); `None` when `NO_PROXY` matches `api.telegram.org` |
| urllib (ad-hoc scripts) | honours `HTTPS_PROXY`/`NO_PROXY`, sends `Proxy-Authorization` from the URL's userinfo |
