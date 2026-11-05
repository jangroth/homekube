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
| `TELEGRAM_BOT_TOKEN` | `/opt/data/.env` (PVC) | Telegram Bot API, HTTPS; token is in the URL path | Only if substitution covers paths (§9 Q2) |
| Aperture `api_key` | `/opt/data/config.yaml` | LLM calls via `http://ai.taild13083.ts.net` over the tailscale sidecar | Not a credential: dummy value, Aperture authenticates by tailnet identity and holds the upstream LLM keys |
| `nous` OAuth tokens | `/opt/data/auth.json` | Nous provider | No: refreshing OAuth tokens |
| `API_SERVER_KEY` | sealed secret `hermes-secrets` | inbound auth to Hermes's API | No: inbound |
| `TS_AUTHKEY` | sealed secret `hermes-secrets` | tailscale sidecar | No: not HTTP |
| `STATE_EXPORT_SSH_KEY` | sealed secret `hermes-secrets` | state-export sidecar, git over SSH | No: SSH, other container |

- Hermes is Python; `SSL_CERT_FILE` and `REQUESTS_CA_BUNDLE` already point at a combined bundle built by the `build-ca-bundle` init container (system store + the chart's `caCert` value); `NODE_EXTRA_CA_CERTS` points at `caCert` alone.
- Dex is reached as `https://pi0.taild13083.ts.net/dex`, Aperture as `http://ai.taild13083.ts.net`; both by hostname.
- No `HTTPS_PROXY` is set. The herminator chart has no `extraEnv` value and no NetworkPolicy template.
- The tailscale sidecar runs in kernel mode (`TS_USERSPACE=false`) in the pod's network namespace; Aperture resolves through a `hostAliases` pin to `100.126.29.31`. The sidecar also routes the `192.168.86.240/28` VIPs over the tailnet.
- Agent Vault is present in Infisical `v0.167.0` (`backend/src/ee/services/agent-vault*`). The on-prem default features only disable session-log storage options; no licence check gates the proxy or sessions.
- `infisical/cli` images are published for `arm64`.

## 4. Decisions within this spec

- **Pilot one credential: Tavily.** It is a plain header-authenticated HTTPS API that Hermes uses regularly, so success and failure are easy to see. Telegram follows in this spec only if §9 Q2 resolves; otherwise a later one.
- **One shared proxy, its own namespace.** Deployment `agent-vault-proxy` in namespace `agent-vault`, `infisical/cli` running `infisical agent-vault proxy`, ClusterIP Service. Running it outside the Hermes pod keeps the proxy token and the proxy CA's private key out of the agent's reach (Agent Vault docs). The same proxy later serves Coder workspaces.
- **Proxy talks to Infisical in-cluster** at `http://infisical.infisical.svc:8080` (`INFISICAL_DOMAIN`), bypassing the TLS sidecar. Traffic stays inside the cluster.
- **Proxy token via sealed secret.** It is bootstrap-tier, like Infisical's own keys (decision 079).
- **Traffic policy "service hosts only" if it tunnels other hosts, else "all hosts".** `HTTPS_PROXY` routes all of Hermes's HTTPS through the proxy, and Hermes browses arbitrary sites. If "service hosts only" passes other hosts through as a plain `CONNECT` tunnel, it is used: only Tavily traffic is decrypted and logged. If it rejects other hosts, "all hosts" is used and the proxy decrypts everything but only attaches credentials for the Tavily service. Step 0 decides.
- **`NO_PROXY`** for cluster and tailnet destinations: `.svc`, `.cluster.local`, `.ts.net`, `10.0.0.0/8`, `100.64.0.0/10`, `192.168.86.0/24`, `localhost`, `127.0.0.1`. httpx and urllib ignore the CIDR entries (only `requests` matches them), so the hostname entries carry Aperture and Dex; anything Hermes reaches by IP is checked in step 6.
- **Telegram bypasses the proxy until it is brokered.** Its bot token is in the URL path, which session logs record. Under "all hosts", `api.telegram.org` is in `NO_PROXY` until step 9 brokers it; under "service hosts only" it is tunnelled and never decrypted.
- **Session token delivered as a Secret, not minted in the pod.** Running `infisical agent-vault run` inside the Hermes container would put a machine identity in the agent's environment, which can mint sessions. Instead the session is created in the Infisical UI and the full proxy URL (`http://<session-token>@agent-vault-proxy.agent-vault.svc:<port>`) is sealed into the `hermes` namespace and injected as `HTTPS_PROXY`. The token is still static in the pod, but it is scoped to one bundle, only works at the proxy, is logged per request, and is revocable in one click.
- **Session TTL `never`, revoked by hand.** A fixed TTL would force a reseal and Hermes restart on every expiry, for a token that only works at an in-cluster proxy and for one bundle. Rotating the brokered credentials themselves happens in Infisical and doesn't touch Hermes. Short-lived, automatically minted sessions belong with the Coder work.
- **Session rotation is make-before-break.** A revoked token is presumably rejected for every request the proxy handles, cutting off all proxied web access, not just search. Rotation creates the new session, reseals, restarts Hermes, then revokes the old session. Revoking first is the incident path.
- **Hermes trusts the proxy CA through a new chart value `extraCaCerts`**, appended by `build-ca-bundle` to the combined bundle and to the `NODE_EXTRA_CA_CERTS` file. It is set in homekube-apps, not in the chart's defaults, so a CA change is one homekube-apps PR. The CA is public. Step 0 finds out where it comes from: if Infisical issues it, it changes only when the proxy token is rotated; if the proxy generates it on startup, its data dir must persist (a PVC instead of `emptyDir`) or the CA and key are provided as a sealed secret.
- **`TAVILY_API_KEY` becomes a placeholder** (`agent-vault`) in `/opt/data/.env`, so Hermes still enables the tool; the proxy replaces it (§9 Q1). The real key moves to the access bundle and is removed from the PVC. The key is rotated at Tavily afterwards, since it has sat in plaintext on the PVC and its backups, and probably in Hermes's conversation history and state export, since it was entered through Hermes.
- **Ingress NetworkPolicy on `agent-vault`, no egress policy on Hermes.** The proxy accepts traffic from namespace `hermes` only, so a leaked session token can't be used from other pods. Egress isn't restricted: the real credential is no longer in the pod, so bypassing the proxy only means sending requests without it. Locking egress down needs allow-rules for the tailscale sidecar's WireGuard/DERP traffic and belongs with the Coder work, where untrusted code makes it essential.
- **Chart changes land in herminator**: optional `extraEnvFrom` for `HTTPS_PROXY` and `extraEnv` for `NO_PROXY`, and `extraCaCerts`, all empty by default. homekube-apps only sets values.

## 5. Target state

### 5a. `homekube-apps/applications/wave-03-apps/agent-vault.yaml`

Plain manifests (no chart exists), via an ArgoCD `Application` pointing at `applications/wave-03-apps/agent-vault/`, sync wave `3`, `CreateNamespace=true`. Added to `applications/kustomization.yaml`.

| File | Content |
|---|---|
| `deployment.yaml` | 1 replica, `infisical/cli:<pinned>` (Renovate-tracked), args `agent-vault proxy`, env `INFISICAL_DOMAIN`, proxy token from `agent-vault-proxy-token`; data dir `emptyDir`, or a PVC if the CA is generated locally (§4); readiness and liveness probes on the endpoint step 0 finds; resources `32Mi` / `10m` → `128Mi` / `200m` (initial guess, check in step 6); data-plane node affinity; non-root, read-only root filesystem |
| `service.yaml` | ClusterIP `agent-vault-proxy`, HTTP port per step 0 |
| `networkpolicy.yaml` | Ingress to `agent-vault-proxy` from namespace `hermes` on the proxy port only |
| `proxy-token-sealedsecret.yaml` | Secret `agent-vault-proxy-token` |

### 5b. Infisical (UI, human step)

- Agent Vault project; proxy `homekube` with the traffic policy step 0 settles (§4) and the default poll interval (value recorded in step 0)
- Service `tavily`: host `api.tavily.com`, credential `TAVILY_API_KEY` with the auth placement step 0 finds, methods/paths limited to what Hermes calls
- Access bundle `hermes` containing `tavily`
- Session on bundle `hermes`, label `hermes`, TTL `never`

### 5c. Hermes

- herminator chart: optional `extraEnvFrom`, `extraEnv` and `extraCaCerts`, empty by default, with a `chart/tests` case that the chart renders unchanged without them; released by merging to herminator `main`, which the `hermes` Application tracks at `HEAD`
- homekube-apps `wave-03-apps/hermes.yaml` values: `NO_PROXY` via `extraEnv`, `extraCaCerts` with the proxy CA, and `extraEnvFrom` referencing sealed secret `hermes-agent-vault` (key `HTTPS_PROXY`), sealed for namespace `hermes`
- `/opt/data/.env`: `TAVILY_API_KEY=agent-vault`

## 6. Execution plan

0. **Verify:**
   - Proxy: HTTP port, flags and a health endpoint (`infisical agent-vault proxy --help`); whether it runs non-root with a read-only root filesystem; where its CA comes from (issued by Infisical or generated on startup into the data dir, §4); whether it keeps serving cached credentials or fails closed while Infisical is down; the default poll interval.
   - Traffic policy: whether "service hosts only" tunnels other hosts or rejects them (§4); what a revoked token gets back from the proxy.
   - Substitutions: how Hermes authenticates to Tavily (header or JSON body) and whether a substitution covers it (§9 Q1); whether substitutions apply to URL paths (§9 Q2).
   - Session logs: whether they are stored on unlicensed self-hosted, and what they record.
   - Hermes clients: whether its HTTP clients honour `HTTPS_PROXY`/`NO_PROXY` (httpx's `trust_env`; python-telegram-bot sets its own client).
   - Current `infisical/cli` tag; that Agent Vault works on unlicensed self-hosted by creating a proxy in the UI.
1. In Infisical: create the project, proxy, service, bundle and session (5b). Store the proxy token and session token in the password manager. *(human step)*
2. Seal `agent-vault-proxy-token` (namespace `agent-vault`) and `hermes-agent-vault` (namespace `hermes`). *(human step)*
3. PR to `homekube-apps`: 5a. Merge, sync, check the proxy shows as connected in the Infisical UI.
4. PR to herminator: chart changes (5c). PR to `homekube-apps`: Hermes values. Merge herminator first.
5. Set `TAVILY_API_KEY=agent-vault` in `/opt/data/.env`, restart Hermes. Ask Hermes for a web search. *(human step)*
6. Check: the session log shows the Tavily request with credentials attached; a non-Tavily HTTPS fetch works; Aperture and Dex calls still work (bypass); Telegram still works and no `api.telegram.org` request is in the session log; nothing Hermes reaches by IP fails on the proxy; a pod outside `hermes` can't connect to the proxy; proxy memory use.
7. Rotation: create a new session, reseal `hermes-agent-vault`, restart Hermes, then revoke the old session; check searches keep working. Then revoke the new session and check search (and, under "all hosts", all proxied web access) fails within one poll interval; create another session and reseal to recover. This is the rotation runbook.
8. Rotate the Tavily key at Tavily, update the service in Infisical. *(human step)*
9. Telegram, if §9 Q2 allows: add a `telegram` service to the bundle, drop `api.telegram.org` from `NO_PROXY` if present, repeat 5–6.
10. CHANGELOG entry; amend decision 080 with the traffic policy and anything else that differs; set this spec to Done.

## 7. Acceptance criteria

- [ ] `agent-vault-proxy` Ready on arm64, connected to Infisical, reachable only from namespace `hermes`
- [ ] No real Tavily key in the Hermes pod's env, `/opt/data/.env` or `config.yaml`; the key Hermes held before is rotated, covering copies in its history, state export and backups
- [ ] Hermes web search works; the session log shows the request with the credential attached
- [ ] Revoking the session stops credential injection within one poll interval
- [ ] Hermes's general web access, Aperture LLM calls and Dex login unaffected
- [ ] No Telegram request appears in the session log with the real token in its path
- [ ] Proxy token and session token in the password manager
- [ ] Rotation runbook (new session → reseal → restart → revoke old; CA change → `extraCaCerts` in homekube-apps) in the homekube-apps README

## 8. Risks

- **Licensing.** Agent Vault lives in Infisical's `ee/` directory, which the repo describes as "premium enterprise features requiring a Infisical license", yet nothing in `v0.167.0` gates it. Fine for a study cluster; recorded in the decision entry.
- **Young feature.** Agent Vault has had roughly one DB migration a week since 2026-09. Infisical bumps are already backed up before merge (spec 009).
- **Proxy as a single point of failure** for Hermes's brokered calls. Unbrokered HTTPS also flows through it, so a proxy outage breaks Hermes's web access too.
- **Infisical as a dependency of Hermes's web access.** The proxy validates sessions and fetches credentials from Infisical; if it fails closed (step 0), an Infisical or Postgres outage takes Hermes's web access down with it.
- **Decryption.** Under "all hosts" every HTTPS request from Hermes is decrypted by the proxy; under "service hosts only" only brokered hosts are. Session logs record method, host, path and status of what is decrypted.

## 9. Open questions for Jan

1. **Tavily auth placement.** If Hermes sends the key in the JSON body rather than a header, does a substitution cover request bodies? Step 0.
2. **Telegram.** The bot token is in the URL path (`/bot<token>/…`). Does a substitution replace it there? If not, Telegram stays on the PVC and outside the proxy (§4).
3. ~~**Session TTL.**~~ Resolved 2026-11-05: `never`, revoked by hand (§4).
4. ~~**Aperture `api_key` in git.**~~ Resolved 2026-11-05: a dummy value; Aperture authenticates by tailnet identity.

## 10. Rollback

Remove `extraEnvFrom`, `extraEnv` (`NO_PROXY`) and `extraCaCerts` from the Hermes values, put the real Tavily key back into `/opt/data/.env`, restart Hermes. Delete the `agent-vault` Application (finalizer removes the namespace contents), then the namespace. Delete the project in Infisical.

## 11. Out of scope

Coder workspaces, egress NetworkPolicy, automated session minting, the Infisical operator, brokering non-HTTP credentials, moving `API_SERVER_KEY`/`TS_AUTHKEY`/state-export key out of sealed-secrets.
