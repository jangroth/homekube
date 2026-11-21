# Research: per-task attribution at Aperture

Answers #103 (Research: per-task attribution at Aperture). Checked on 2026-11-21 against Tailscale's Aperture docs (pages marked "Last validated Sep 28, 2026"), the `jangroth/ai-gateway` repo and a read-only look at session records through the Aperture MCP tools.

**Question:** can Aperture attribute requests to a task (a request header, tag, metadata field or per-task key), or only to the calling tailnet identity? What does its usage and session reporting show?

## Answer

Identity, access and quotas are keyed only on the calling tailnet identity. Below that, there are two ways to tell tasks apart in reporting:

1. **Sessions.** Aperture groups requests into sessions from a client-supplied ID. For Claude Code this is the session ID in each request body, so each Claude Code run in a workspace shows up as its own session, even behind one shared identity.
2. **Indexed headers.** An admin can index chosen request headers (for example `x-homekube-task`) and filter the Logs, usage and activity pages by their value.

Neither one is an identity. A header or session can't select a grant, a model allow-list or a quota bucket. A per-task key doesn't exist either: clients carry no Aperture key.

## Findings

### Identity comes only from Tailscale

- Every request is authenticated by Tailscale identity. "Every metric record includes the login name and device ID" ([how Aperture works](https://tailscale.com/docs/aperture/how-aperture-works)).
- A tagged device with no user gets a synthetic login name: its tags sorted and joined by commas, e.g. `tag:api,tag:prod`. That name appears "in usage views, logs, and session tracking" ([how Aperture works, tagged device identity](https://tailscale.com/docs/aperture/how-aperture-works)).
- If several people share one bridge instance, "all activity appears under the same identity" ([how Aperture works](https://tailscale.com/docs/aperture/how-aperture-works); [connect from outside the tailnet](https://tailscale.com/docs/aperture/connect-outside-tailnet)). The shared egress from ADR-0020 is exactly this case: every workspace appears as the egress node's tag identity.
- Grant `src` takes users, groups and tags only ([how grants work](https://tailscale.com/docs/aperture/how-grants-work)). Nothing in a grant matches a header or session.
- Quota bucket names expand only `<user>` (login name or tag set) and `<node>` (node ID) ([configuration: quotas, template variables](https://tailscale.com/docs/aperture/configuration)). Behind one egress node both expand to one value, so per-task budgets can't be enforced at Aperture.
- Clients send a placeholder key such as `-`, and Aperture adds the provider key ([how to use Claude Code](https://tailscale.com/docs/aperture/how-to/use-claude-code); [troubleshooting](https://tailscale.com/docs/aperture/troubleshooting)). `auth_mode: "passthrough"` forwards a client's own provider key upstream ([configuration](https://tailscale.com/docs/aperture/configuration)), so at most it gives attribution at the provider. Aperture still files the request under the tailnet identity.

### Sessions: grouped by a client-supplied ID

- "Aperture identifies sessions using client-supplied identifiers or, when possible, a fingerprint of conversation content": Claude Code puts a session ID in each request body, Codex sends it as an HTTP header, OpenAI Chat gets a content fingerprint. Any other request gets a random ID and counts as a session of its own ([how Aperture works, session tracking](https://tailscale.com/docs/aperture/how-aperture-works)).
- The session ID is in every hook call as `metadata.session_id`, next to `login_name`, `user_agent`, `stable_node_id`, `request_id`, `model` and `provider` ([configuration: hook metadata](https://tailscale.com/docs/aperture/configuration)). It is also a field of every S3 export record, next to `identity` (login name, stable node ID, tags) and `capture`, which includes the headers ([export usage data to S3](https://tailscale.com/docs/aperture/how-to/export-usage-data-to-s3)).
- The docs don't describe a way to *set* the session ID. It comes from the client and should be treated as an opaque string ([configuration: hook metadata](https://tailscale.com/docs/aperture/configuration)).
- **Observed (MCP, read-only):** a session record has a Session ID (`ancc_…` for Claude Code), a title taken from the first prompt (e.g. "Issue #31"), the agent ("Claude Code"), models, start and last-active times, request count, input/cached/output tokens, estimated cost and a count of tool calls. Each request has a capture ID, model, status, duration, tokens, cost, tools and the prompt. The listing has no identity column: `list_sessions` shows only the caller's own sessions.

### Indexed headers: filterable, not enforceable

- Headers are stored in captures but not indexed by default. `database.headers.filterable` lists the header names to index. An admin also needs a grant capability `filterable_headers` before anyone, admins included, can filter on a header ([configuration: `database.headers`](https://tailscale.com/docs/aperture/configuration); [filter logs by header](https://tailscale.com/docs/aperture/how-to/filter-logs-by-header)).
- Header filters work on the User Dashboard, Usage Overview, Model Activity, Agent Activity, Logs and Tool Use pages. Matches can be **Present**, **Contains** or **Is exactly** ([configuration: `database.headers`](https://tailscale.com/docs/aperture/configuration); [admin dashboard reference](https://tailscale.com/docs/aperture/reference/dashboard-admin)).
- Indexed values outlive capture retention. With write-time zero retention, though, Aperture writes no new header index values ([configuration: `database`](https://tailscale.com/docs/aperture/configuration)). Per-task header attribution therefore needs capture retention above zero.
- The docs suggest "low-cardinality, stable headers that identify or classify a request", such as a routing or trace ID ([filter logs by header](https://tailscale.com/docs/aperture/how-to/filter-logs-by-header)). A per-task ID fits that shape.
- Hooks don't get headers as a `send` option (the choices are `tools`, `request_body`, `user_message`, `response_body`, `raw_responses`, `estimated_cost`, `grants`, `quotas`, `revisions`). Of the headers, only `user_agent` appears in hook metadata ([configuration: hooks](https://tailscale.com/docs/aperture/configuration)).
- Claude Code can send extra headers through `ANTHROPIC_CUSTOM_HEADERS` (`Name: Value`, one per line) ([Claude Code env vars](https://code.claude.com/docs/en/env-vars)). A workspace could set `x-homekube-task: <task>` itself, or the egress proxy could add it. Since every workspace shares one egress, the proxy can only add a value the workspace sends it.

### Current gateway setup (`jangroth/ai-gateway`)

- The tailnet policy gives Aperture `role: user` with `models: "**"` to `src: ["*"]`, and `admin` to `group:owner` and `tag:ci` (`tailnet/policy.hujson`). Git manages only the `providers` section, while `database`, quotas and the rest stay in the gateway UI (`README.md`). Nothing in the repo configures `database.headers`, so no headers are indexed yet unless someone set it in the UI.
- The `aperture-egress` deployment from ADR-0020 doesn't exist in `homekube-apps` yet, so there was no live request from it to inspect.

## Caveats

- Session IDs depend on the client. A task that calls the Anthropic API directly, with no Claude Code session ID, gets a random ID per request and can't be grouped.
- A header is something the client asserts. It's fine for reporting but can't be trusted: any workspace behind the egress can send any value. Hermes's logs stay the authoritative per-task record, as ADR-0020 says.
- Header indexing and the `filterable_headers` grant are admin config. Neither is in git today.
- The session-record fields above come from the MCP tool's rendering. The dashboard may show more (e.g. the identity on the Logs page).
