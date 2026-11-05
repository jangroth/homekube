# Spec 010 — Infisical Agent Vault for Hermes

**Status:** Draft (2026-11-04)
**Related decisions:** [Decision 080](../../DECISIONS.md) — Agent Vault for Hermes, ahead of ESO; reorders the phases of [decision 079](../../DECISIONS.md). [Decision 075](../../DECISIONS.md) — Hermes image pins.
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
| 3 | External Secrets Operator, one test secret | later |
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

- Hermes is Python; `SSL_CERT_FILE` and `REQUESTS_CA_BUNDLE` already point at a homekube-ca bundle mounted from the chart (`caCert` value).
- No `HTTPS_PROXY` is set. The herminator chart has no `extraEnv` value and no NetworkPolicy template.
- The tailscale sidecar runs in kernel mode (`TS_USERSPACE=false`) in the pod's network namespace; Aperture resolves through a `hostAliases` pin to `100.126.29.31`.
- Agent Vault is present in Infisical `v0.167.0` (`backend/src/ee/services/agent-vault*`). The on-prem default features only disable session-log storage options; no licence check gates the proxy or sessions.
- `infisical/cli` images are published for `arm64`.

## 4. Decisions within this spec

- **Pilot one credential: Tavily.** It is a plain header-authenticated HTTPS API that Hermes uses regularly, so success and failure are easy to see. Telegram follows in this spec only if §9 Q2 resolves; otherwise a later one.
- **One shared proxy, its own namespace.** Deployment `agent-vault-proxy` in namespace `agent-vault`, `infisical/cli` running `infisical agent-vault proxy`, ClusterIP Service. Running it outside the Hermes pod keeps the proxy token and the proxy CA's private key out of the agent's reach (Agent Vault docs). The same proxy later serves Coder workspaces.
- **Proxy talks to Infisical in-cluster** at `http://infisical.infisical.svc:8080` (`INFISICAL_DOMAIN`), bypassing the TLS sidecar. Traffic stays inside the cluster.
- **Proxy token via sealed secret.** It is bootstrap-tier, like Infisical's own keys (decision 079).
- **Traffic policy "all hosts".** `HTTPS_PROXY` routes all of Hermes's HTTPS through the proxy, and Hermes browses arbitrary sites; "service hosts only" would break that. The proxy decrypts all of it but only attaches credentials for the Tavily service.
- **`NO_PROXY`** for cluster and tailnet destinations: `.svc`, `.cluster.local`, `.ts.net`, `10.0.0.0/8`, `100.64.0.0/10`, `192.168.86.0/24`, `localhost`, `127.0.0.1`.
- **Session token delivered as a Secret, not minted in the pod.** Running `infisical agent-vault run` inside the Hermes container would put a machine identity in the agent's environment, which can mint sessions. Instead the session is created in the Infisical UI and the full proxy URL (`http://<session-token>@agent-vault-proxy.agent-vault.svc:<port>`) is sealed into the `hermes` namespace and injected as `HTTPS_PROXY`. The token is still static in the pod, but it is scoped to one bundle, only works at the proxy, is logged per request, and is revocable in one click.
- **Session TTL `never`, revoked by hand.** A fixed TTL would force a reseal and Hermes restart on every expiry, for a token that only works at an in-cluster proxy and for one bundle. Rotating the brokered credentials themselves happens in Infisical and doesn't touch Hermes. Short-lived, automatically minted sessions belong with the Coder work.
- **Hermes trusts the proxy CA** by adding it to the chart's existing CA bundle. The CA is public; it changes when the proxy token is rotated, which then means a chart value update.
- **`TAVILY_API_KEY` becomes a placeholder** (`agent-vault`) in `/opt/data/.env`, so Hermes still enables the tool; the proxy replaces it (§9 Q1). The real key moves to the access bundle and is removed from the PVC. The key is rotated at Tavily afterwards, since it has sat in plaintext on the PVC and in its backups.
- **No egress NetworkPolicy in this spec.** The real credential is no longer in the pod, so bypassing the proxy only means sending requests without it. Locking egress down needs allow-rules for the tailscale sidecar's WireGuard/DERP traffic and belongs with the Coder work, where untrusted code makes it essential.
- **Chart changes land in herminator**: an `extraEnv`/`envFrom` hook for `HTTPS_PROXY`/`NO_PROXY`, and the proxy CA appended to `caCert`. homekube-apps only sets values.

## 5. Target state

### 5a. `homekube-apps/applications/wave-03-apps/agent-vault.yaml`

Plain manifests (no chart exists), via an ArgoCD `Application` pointing at `applications/wave-03-apps/agent-vault/`, sync wave `3`, `CreateNamespace=true`. Added to `applications/kustomization.yaml`.

| File | Content |
|---|---|
| `deployment.yaml` | 1 replica, `infisical/cli:<pinned>` (Renovate-tracked), args `agent-vault proxy`, env `INFISICAL_DOMAIN`, proxy token from `agent-vault-proxy-token`; `emptyDir` data dir; resources `32Mi` / `10m` → `128Mi` / `200m` (initial guess, check in step 6); data-plane node affinity; non-root, read-only root filesystem |
| `service.yaml` | ClusterIP `agent-vault-proxy`, HTTP port per step 0 |
| `proxy-token-sealedsecret.yaml` | Secret `agent-vault-proxy-token` |

### 5b. Infisical (UI, human step)

- Agent Vault project; proxy `homekube` with traffic policy "all hosts" and the default poll interval
- Service `tavily`: host `api.tavily.com`, credential `TAVILY_API_KEY` with the auth placement step 0 finds, methods/paths limited to what Hermes calls
- Access bundle `hermes` containing `tavily`
- Session on bundle `hermes`, label `hermes`, TTL `never`

### 5c. Hermes

- herminator chart: optional `extraEnvFrom` (or equivalent) and the proxy CA appended to `caCert`; released by merging to herminator `main`, which the `hermes` Application tracks at `HEAD`
- homekube-apps `wave-03-apps/hermes.yaml` values: `NO_PROXY`, and a reference to sealed secret `hermes-agent-vault` (key `HTTPS_PROXY`), sealed for namespace `hermes`
- `/opt/data/.env`: `TAVILY_API_KEY=agent-vault`

## 6. Execution plan

0. **Verify:** proxy HTTP port and flags (`infisical agent-vault proxy --help`), and whether it runs non-root with a read-only root filesystem; how Hermes authenticates to Tavily (header or JSON body) and whether a substitution covers it (§9 Q1); whether substitutions apply to URL paths (§9 Q2); whether Hermes's HTTP clients honour `HTTPS_PROXY`/`NO_PROXY` (httpx's `trust_env`; python-telegram-bot sets its own client); current `infisical/cli` tag; that Agent Vault works on unlicensed self-hosted by creating a proxy in the UI.
1. In Infisical: create the project, proxy, service, bundle and session (5b). Store the proxy token and session token in the password manager. *(human step)*
2. Seal `agent-vault-proxy-token` (namespace `agent-vault`) and `hermes-agent-vault` (namespace `hermes`). *(human step)*
3. PR to `homekube-apps`: 5a. Merge, sync, check the proxy shows as connected in the Infisical UI.
4. PR to herminator: chart changes (5c). PR to `homekube-apps`: Hermes values. Merge herminator first.
5. Set `TAVILY_API_KEY=agent-vault` in `/opt/data/.env`, restart Hermes. Ask Hermes for a web search. *(human step)*
6. Check: the session log shows the Tavily request with credentials attached; a non-Tavily HTTPS fetch works; Aperture calls still work (bypass); proxy memory use.
7. Revoke the session; check a search fails within one poll interval. Create a new session and reseal `hermes-agent-vault` (this is also the rotation runbook).
8. Rotate the Tavily key at Tavily, update the service in Infisical. *(human step)*
9. Telegram, if §9 Q2 allows: add a `telegram` service to the bundle, repeat 5–6.
10. CHANGELOG entry; amend decision 080 if the outcome differs; set this spec to Done.

## 7. Acceptance criteria

- [ ] `agent-vault-proxy` Ready on arm64, connected to Infisical
- [ ] No real Tavily key anywhere in the Hermes pod (env, `/opt/data/.env`, `config.yaml`)
- [ ] Hermes web search works; the session log shows the request with the credential attached
- [ ] Revoking the session stops credential injection within one poll interval
- [ ] Hermes's general web access and Aperture LLM calls unaffected
- [ ] Tavily key rotated after the move
- [ ] Proxy token and session token in the password manager
- [ ] Rotation runbook (new session → reseal → restart; proxy token rotation → new CA → chart value) in the homekube-apps README

## 8. Risks

- **Licensing.** Agent Vault lives in Infisical's `ee/` directory, which the repo describes as "premium enterprise features requiring a Infisical license", yet nothing in `v0.167.0` gates it. Fine for a study cluster; recorded in the decision entry.
- **Young feature.** Agent Vault has had roughly one DB migration a week since 2026-09. Infisical bumps are already backed up before merge (spec 009).
- **Proxy as a single point of failure** for Hermes's brokered calls. Unbrokered HTTPS also flows through it, so a proxy outage breaks Hermes's web access too.
- **Every HTTPS request from Hermes is decrypted by the proxy.** Session logs record method, host, path and status.

## 9. Open questions for Jan

1. **Tavily auth placement.** If Hermes sends the key in the JSON body rather than a header, does a substitution cover request bodies? Step 0.
2. **Telegram.** The bot token is in the URL path (`/bot<token>/…`). Does a substitution replace it there? If not, Telegram stays on the PVC.
3. ~~**Session TTL.**~~ Resolved 2026-11-05: `never`, revoked by hand (§4).
4. ~~**Aperture `api_key` in git.**~~ Resolved 2026-11-05: a dummy value; Aperture authenticates by tailnet identity.

## 10. Rollback

Delete `HTTPS_PROXY` from Hermes (remove the values reference), put the real Tavily key back into `/opt/data/.env`, restart Hermes. Delete the `agent-vault` Application (finalizer removes the namespace contents), then the namespace. Delete the project in Infisical.

## 11. Out of scope

Coder workspaces, egress NetworkPolicy, automated session minting, ESO, brokering non-HTTP credentials, moving `API_SERVER_KEY`/`TS_AUTHKEY`/state-export key out of sealed-secrets.
