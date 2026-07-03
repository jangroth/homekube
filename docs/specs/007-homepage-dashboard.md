# Spec 007 — Homepage Dashboard

**Status:** Implemented (2026-07-03)
**Repos:** `homekube-apps` (ArgoCD app manifest + config) **and** `homekube-main` (the ArgoCD `apiKey` account + RBAC for the ArgoCD widget live in the Ansible-managed ArgoCD Helm values — `argocd-cm`/`argocd-rbac-cm` are Helm-owned, not editable via the `argocd-config` app; see Rollout §2)
**Relates to:** `docs/specs/005-production-cluster-setup.md` — this is a cross-cutting landing page that surfaces the services stood up across all of Phase 5's waves. Written as its own spec (not a 005 capability) because it depends on the *outputs* of 005 rather than sitting inside its wave dependency graph.

---

## Problem

Phase 5 has produced a growing set of web UIs — ArgoCD, Longhorn, Grafana, Prometheus, Alertmanager, Dex — each on its own LB VIP or NodePort. There is no single entry point: reaching any of them means remembering an IP and port. We want a **single dashboard** that lists every cluster service with a clickable link, live status, and (where cheap) a widget or two, so the cluster has a front door.

[Homepage](https://gethomepage.dev) (gethomepage) is the target: YAML-configured, GitOps-friendly, first-class Kubernetes support (service discovery via annotations, a cluster-resource widget backed by metrics-server, and per-service widgets for the tools we already run).

---

## Current State

| Thing | State |
|---|---|
| Service exposure | Cilium LB-IPAM VIPs `192.168.86.241–251`; `.241` ArgoCD, `.242` Longhorn, `.243` Grafana, `.244` Dex. Next free: **`.245`** |
| Reachability | VIPs reachable from `darth` over Tailscale (subnet routes on all 4 nodes) and from home Wi-Fi. Not public. |
| metrics-server | Running (`kubectl top` works) — the cluster-resource widget depends on it |
| Identity / SSO | Dex (cap-9) live; Google OIDC federates ArgoCD + Grafana. Homepage has **no OIDC integration of its own** and no auth. |
| Ingress | None. No Gateway API, no forward-auth proxy. Discovery-by-Ingress-annotation is therefore not available yet. |

---

## Decisions (confirmed with user 2026-07-02)

1. **Product: Homepage** (gethomepage.dev) — not Heimdall/Homer.
2. **Standalone spec 007** — not a capability inside 005.
3. **Auth: open on the LB VIP, SSO deferred.** Homepage ships no login. It is reachable only over Tailscale / home Wi-Fi, never public, so an unauthenticated dashboard is an accepted risk for now. Real SSO (forward-auth proxy → Dex, or Gateway API ingress with auth) is deferred with the ingress story (see 005 Deferred list). Record as a DECISION.
4. **Integration depth: auto-discovery + credentialed widgets.** A ServiceAccount with cluster read RBAC drives the Kubernetes cluster-resource widget and annotation-based discovery; per-service widgets (ArgoCD, Longhorn, Prometheus, Grafana) pull live status, with any required API tokens stored as **sealed-secrets** — no plaintext creds in git.

---

## Version Policy

Per 005's Version Policy: track latest upstream GA, re-verify at implementation. **Re-verify before committing** — checked 2026-07-02, stale in ~30 days.

| Component | Latest (2026-07-02) | Notes |
|---|---|---|
| Homepage image | **v1.13.2** | `ghcr.io/gethomepage/homepage:v1.13.2` — official, upstream-published, multi-arch (arm64). This is the only real dependency. |

> **No Helm chart.** Upstream ships no official chart and labels the community ones ("unofficial"). Both candidates (`jameswynn/homepage`, `M0NsTeRRR`) are single-maintainer repos with low activity and unresponsive issue trackers — a poor dependency for the cluster's front door. We instead vendor upstream's own documented **raw manifests** and depend only on the official image. See "Install method" below.
>
> **ARM64 pre-flight** (005 convention): `crane manifest --platform linux/arm64 ghcr.io/gethomepage/homepage:v1.13.2` must resolve before committing.

---

## Approach

### Install method: vendored raw manifests (not a chart)

An ArgoCD `Application` with a **single git source** pointing at a directory of hand-maintained manifests under `homekube-apps`, adapted from [Homepage's official k8s docs](https://gethomepage.dev/installation/k8s/). No Helm. This differs from the chart-based apps (`dex.yaml` etc.) but is the right call here: the config *is* the manifests, we pin the official image ourselves, and there's no third-party chart maintainer to depend on. ArgoCD syncs a plain manifest directory as readily as a chart.

Directory `applications/wave-03-apps/homepage/`, with the ArgoCD `Application` manifest (`homepage.yaml`) beside it — matching the repo's wave-NN-apps convention. (The repo's existing convention is `<app>.yaml` + `<app>-extras/`, but "extras" denotes supplements to a Helm chart; here the raw manifests *are* the app, so a plain `homepage/` dir is clearer. `homepage.yaml` points a single git source at that dir — the same self-referencing pattern `dex.yaml`/`prometheus-extras.yaml` already use.)

| File | Contents |
|---|---|
| `namespace.yaml` | `homepage` namespace |
| `rbac.yaml` | ServiceAccount + ClusterRole (read-only) + ClusterRoleBinding. No standalone token Secret — with `mode: cluster` Homepage uses the pod's mounted SA token; upstream's token Secret is only for out-of-cluster access. |
| `configmap.yaml` | Homepage config files: `settings.yaml`, `services.yaml`, `widgets.yaml`, `bookmarks.yaml`, `kubernetes.yaml` |
| `deployment.yaml` | `ghcr.io/gethomepage/homepage:v1.13.2`, config volume mount, probes, `HOMEPAGE_ALLOWED_HOSTS`, `envFrom` sealed-secret, **homekube-CA volume mount + `NODE_EXTRA_CA_CERTS`** (required — the ArgoCD & Grafana widgets fetch over in-cluster HTTPS; see §3), `nodeAffinity` off pi0 |
| `service.yaml` | `type: LoadBalancer`, `io.cilium/lb-ipam-ips: "192.168.86.245"`, port 80 → container `:3000` |
| `sealedsecret.yaml` | `homepage-widget-secrets` (see §5) |

- **Exposure:** LB VIP `192.168.86.245`, HTTP. HTTPS deferred — consistent with Grafana's cap-8 posture before OIDC; no browser-trust story needed for an internal dashboard yet.
- **Config:** the ConfigMap holds Homepage's YAML files verbatim, mounted at the config path. Editing the dashboard = editing `configmap.yaml` + ArgoCD sync.
- **RBAC:** our own ServiceAccount + ClusterRole/ClusterRoleBinding granting read on the resources Homepage discovers and the metrics widget needs — no chart magic to reverse-engineer.
- **Widget secrets:** a sealed-secret (`homepage-widget-secrets`) in the `homepage` namespace, surfaced to the pod as `HOMEPAGE_VAR_*` env vars and referenced in widget config as `{{HOMEPAGE_VAR_...}}`.

### Wave / rollout placement

Homepage depends on services from waves `-1` through `02` all being up, so it lands **after cap-8/cap-9**: `applications/wave-03-apps/homepage.yaml`, appended to `applications/kustomization.yaml`, annotated `argocd.argoproj.io/sync-wave: "3"` so it reconciles after everything it links to. It is inert with respect to the rest of the cluster — pure read + a web UI — so ordering only affects whether widgets find their targets on first sync, not correctness.

---

## Components & Configuration

### 1. Kubernetes integration (`kubernetes.yaml` + RBAC)

- `kubernetes.yaml`: `mode: cluster` (in-cluster ServiceAccount).
- ClusterRole (read-only) covering: `pods`, `nodes`, `services`, `namespaces`, `endpoints` (core); `ingresses` (networking) for future annotation discovery; `metrics.k8s.io` (`nodes`, `pods`) for the resource widget. Lift the exact rule set from upstream's documented `ClusterRole` and trim to what we use.

### 2. Cluster-resource widget (`widgets.yaml`)

- `kubernetes` widget: cluster CPU / memory / node count, via metrics-server.
- `resources` widget: optional CPU/mem/disk of the Homepage node.
- `search` + `datetime` (timezone `Australia/Sydney`, matching Grafana).

### 3. Service listing (`services.yaml`)

Static, hand-maintained entries are the **reliable** population path (no Ingress means annotation discovery has little to read yet). One group per concern, each with `href`, `icon`, and where cheap a `widget`:

| Service | href (browser link) | Widget | Widget `url` (in-cluster) | Auth needed |
|---|---|---|---|---|
| ArgoCD | `https://192.168.86.241` | `argocd` (app health counts) | `https://argocd-server.argocd.svc` (TLS — see gotcha) | **API token** → sealed-secret |
| Longhorn | `http://192.168.86.242` | `longhorn` — an **info widget** (top bar, `widgets.yaml`), not a service widget (found at implementation: service-widget type `longhorn` doesn't exist) | `http://longhorn-frontend.longhorn-system.svc` | none (reads Longhorn API) |
| Grafana | `https://192.168.86.243` | — (link only; see Open Question 2 resolution) | — | none |
| Prometheus | `http://<node>:30002` | `prometheus` (targets up/down) | Prometheus `Service` in `observability`, `:9090` | none (internal) |
| Alertmanager | `http://<node>:30004` | — (link only) | — | none |
| Dex | `https://pi0.taild13083.ts.net/dex` | — (link only) | — | none |

> **href vs widget `url` (TLS gotcha):** Homepage supports a per-service split between `href` (what the browser opens — the VIPs) and the widget's `url` (what the pod fetches). Keep them separate, and mind that **not every widget backend speaks plain HTTP in-cluster**:
> - **Longhorn, Prometheus** — plain HTTP in-cluster; widget `url` uses service DNS over `http://` (also avoids hairpinning through the LB).
> - **ArgoCD** — HTTPS-only in-cluster, serving a `homekube-ca` cert: cap-9 removed `server.insecure` (commit `b4135ed`), so `argocd-server:80` now redirects to TLS. There is **no** plain-HTTP endpoint to point the widget at. Homepage's widget fetches run in Node.js, which rejects untrusted CAs, so the widget must fetch over HTTPS **with the homekube-CA trusted**: mount the `homekube-ca` cert into the pod and set `NODE_EXTRA_CA_CERTS` (see `deployment.yaml` above). This is a hard requirement, not a fallback. (Grafana is also HTTPS-only in-cluster, but per Open Question 2 it gets no widget, so only ArgoCD drives this requirement.)
>
> Verify exact Service names/ports at implementation. For the NodePort `href`s, pin whichever node address is used to reach them today — the widget path doesn't depend on it.

> **Grafana widget caveat (resolved 2026-07-03 — widget dropped):** see Open Question 2. The widget unconditionally fetches `/api/admin/stats`, which requires Grafana *server-admin*; no viewer-grade credential can render it. Grafana is listed link-only.

### 4. Annotation-based discovery (forward-looking)

Enable discovery so future workloads self-register by adding annotations to their `Service`/`Ingress`:

```yaml
gethomepage.dev/enabled: "true"
gethomepage.dev/name: "My App"
gethomepage.dev/group: "Apps"
gethomepage.dev/icon: "my-app.png"
gethomepage.dev/href: "http://..."
```

Optionally back-fill these onto the existing LB Services so the static list and discovery converge. Not required for acceptance.

### 5. Sealed-secret (`homepage-widget-secrets`)

- Keys: `HOMEPAGE_VAR_ARGOCD_TOKEN` only (the Grafana key was dropped with the widget — Open Question 2).
- Sealed per-namespace (`homepage`) with `kubeseal`, committed to the manifest directory.
- Deployment wiring: `envFrom: [{ secretRef: { name: homepage-widget-secrets } }]`.

### 6. `HOMEPAGE_ALLOWED_HOSTS` (gotcha)

Since v1.0, Homepage rejects requests whose `Host` header isn't allow-listed. Set:

```
HOMEPAGE_ALLOWED_HOSTS: "192.168.86.245"
```

The VIP alone suffices: browsing from darth over Tailscale subnet routes still sends `Host: 192.168.86.245` — there is no `.ts.net` name serving Homepage. Add further entries only if a DNS name or Tailscale-serve proxy is later put in front. A wrong/missing entry returns a blank page / "host not allowed" error. Easy to miss.

---

## Resource Budget

| Component | RAM request | Notes |
|---|---|---|
| Homepage | 128 MiB (limit ~256 MiB) | single replica, stateless |

Comfortable within 005's headroom. `nodeAffinity` to keep it off `pi0` (match the pattern used by Dex/Prometheus).

---

## Acceptance

- [x] `kubectl get pods -n homepage` — Homepage pod Running
- [x] Dashboard reachable on LB VIP `192.168.86.245` from `darth` (Tailscale); no "host not allowed" error. *Home Wi-Fi not verified — the Wi-Fi LB path is slated for removal (TODO Backlog: "Drop Wi-Fi LB access; go Tailscale-only").*
- [x] Kubernetes cluster-resource widget renders live CPU/memory and lists all 4 nodes (metrics-server path works)
- [x] Every core service (ArgoCD, Longhorn, Grafana, Prometheus, Alertmanager, Dex) is listed with a working link
- [x] ArgoCD widget shows live app-health counts (sealed API token works)
- [x] Longhorn widget shows volume/node health (as top-bar *info* widget — see services table note)
- [x] Prometheus widget renders live status (Grafana is link-only per Open Question 2)
- [x] No plaintext credentials anywhere in `homekube-apps` (all via `homepage-widget-secrets`)
- [x] `applications/kustomization.yaml` includes the new manifest; ArgoCD shows the app Synced/Healthy
- [x] README "Deployed Components" table updated with the Homepage row ([[feedback_readme_maintenance]])

---

## Rollout

1. Re-verify the image tag; run the arm64 `crane` pre-flight on `ghcr.io/gethomepage/homepage:v1.13.2`.
2. Mint the widget credential, then `kubeseal` it into `homepage-widget-secrets`:
   - **ArgoCD:** declare a local account with capability `apiKey` **only** (no `login`) plus a read-only RBAC entry, then generate the token. **These go in the Ansible ArgoCD Helm values in `homekube-main`** — `argocd-cm`/`argocd-rbac-cm` are Helm-owned (cap-9 commit `f0e9988`: "Helm is the sole owner of argocd-cm and argocd-rbac-cm"), *not* editable via the `argocd-config` app's extras dir (which holds only `argocd-service.yaml`). Source-reflects-runtime therefore lands in homekube-main. `apiKey`-only keeps the token working when the cap-9 follow-up disables local UI login.
   - ~~**Grafana:** provision a viewer-role service-account token~~ — dropped; see Open Question 2.
3. Write the manifest directory `applications/wave-03-apps/homepage/` (namespace, rbac, configmap, deployment, service, sealedsecret) and the ArgoCD `Application` (`homepage.yaml`, single git source).
4. Append `homepage.yaml` to `applications/kustomization.yaml`.
5. Sync via ArgoCD; walk the acceptance list.
6. Update README, CHANGELOG, DECISIONS (open-on-VIP auth posture), TODO.

---

## Open Questions

1. ~~Which Helm chart?~~ **Resolved:** no chart. Both community charts are stale, single-maintainer, low-activity, unresponsive to issues/PRs — not a dependency worth taking for the cluster's front door. Use upstream's documented raw manifests, vendored into the repo, depending only on the official `ghcr.io/gethomepage/homepage` image. (Decided with user 2026-07-02; record in DECISIONS.)
2. ~~Grafana widget auth~~ **Resolved 2026-07-03: no Grafana widget — link only.** Tested during implementation: the widget's auth is basic-auth-only, and while Grafana accepts an SA token as basic auth (`api_key:<token>` — verified 200 on `/api/search` and the alerts endpoints with a Viewer token), the widget *unconditionally* fetches `/api/admin/stats` for its dashboard/datasource counts. That endpoint requires Grafana **server-admin** (Viewer token: 403, verified), and the component renders an error state on any stats failure — no `fields` setting skips the call (checked `widget.js`/`component.jsx`/`use-widget-api.js` at implementation time). The alternatives — a server-admin token or the admin password in the pod env of an unauthenticated dashboard — were rejected (decided with user 2026-07-03; record in DECISIONS). The Grafana SA created during implementation was deleted again; `homepage-widget-secrets` carries only the ArgoCD token. Prometheus's widget covers live monitoring status.
