# Changelog

All notable changes to the homekube project (`homekube/`, `homekube-main/`, `homekube-apps/`).

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Entries are reverse-chronological; each dated section groups changes by type:

- **Added** — new components, files, or capabilities
- **Changed** — modifications to existing config, versions, or behaviour
- **Removed** — deletions and decommissioning
- **Fixed** — bug fixes
- **Operational** — manual interventions, recoveries, one-off ops actions
- **Decisions** — links to `DECISIONS.md` entries created on this day

Cross-repo entries reference commits as `repo@sha` (e.g. `homekube-main@e77a322`). Where a change has an associated decision or spec, link it inline.

Current quarter only. Prior quarters: [2026 Q2](CHANGELOG-2026-Q2.md).

---

## 2026-09-01

### Added
- `homekube-main/terraform/bootstrap-identity/`: two IAM Identity Center permission sets (`homekube-terraform` least-privilege, `homekube-readonly` AWS-managed `ReadOnlyAccess`) and two attribution-only IAM roles (`homekube-agent-terraform`/`homekube-agent-readonly`) Claude assumes on top of Jan's SSO session for CloudTrail-distinguishable, non-standing access. Applied with Jan's admin SSO profile (one-time, privileged bootstrap step).
- `homekube-main/terraform/backup-target/`: S3 bucket (`homekube-backups-010316939032-ap-southeast-2-an`, account-regional namespace), public-access block, 30-day lifecycle safety net, and IAM user `homekube-backup` with bucket-scoped credentials for Longhorn/Velero. Applied under the `homekube-terraform` SSO profile. Closes issue #20, unblocks #19/#21.

### Decisions
- [059](DECISIONS.md#059--apply-spec-008-s3-backup-target--scoped-terraform-identity-2026-09-01): applied spec 008 — storage-class rationale, tagging as first-class, and the IAM Identity Center permission-set reprovisioning gotcha.

---

## 2026-08-23

### Fixed
- `homekube-apps@ba50b7b`: `CPUThrottlingHigh` (severity=info) was firing continuously on all 4 node-exporter pods plus the grafana-sc-dashboard sidecar — their CPU limits are intentionally tight for the Pi-scale budget, so brief bursts tripped the default threshold with no actual degradation, and the alertmanager route had no severity split so it paged Telegram same as anything critical. Added a `severity=info` sub-route to the `null` receiver; alert stays visible in Prometheus/Grafana, stops paging. Closes issue #3. See decision 057.

### Decisions
- [057](DECISIONS.md#057--route-severityinfo-alerts-to-null-receiver-instead-of-disabling-or-resizing-2026-08-23): scoped issue #3 via the live cluster's active alerts, routed info-severity noise away from Telegram instead of disabling the rule or resizing CPU limits.

---

## 2026-08-22

### Changed
- `homekube-main@d965291`: systemd runtime watchdog timeout raised 1min → 10min on all 4 nodes (new `configure_watchdog.yml` task in `k8s-node` role, drop-in `/etc/systemd/system.conf.d/50-homekube-watchdog.conf`). The vendor 1min timeout has fired four times under pod-churn load stalls and the reset never self-recovered a node (issue #22); the kernel pets the BCM2835 beyond its hardware window, so the longer timeout still guards real hangs. Applied live via ad-hoc copy + `daemon-reexec`, verified `RuntimeWatchdogUSec=10min` on all nodes.

### Fixed
- `homekube-apps@83fc330` (+ prior commit): `prometheus` ArgoCD app stuck `OutOfSync`/`Sync failed` since 2026-07-22. Grafana admin password was being regenerated every reconcile (Helm `lookup` unusable under ArgoCD's `helm template` rendering) — now pinned via a sealed `existingSecret`. The resulting selfHeal re-sync churn was racing the chart's Job-based admission-webhook cert hook, which ArgoCD misreported as failed even though the Job always succeeded — switched to `prometheusOperator.admissionWebhooks.certManager.enabled: true` to remove the Job/hook mechanism entirely. See decision 053.
- `homekube-main@b81897b` + `homekube-main@22b8768`: pi0's `netplan-eth0` NetworkManager profile had no interface-name restriction, so NetworkManager was also fighting Cilium's `cilium_host`/`lxc*` veths with endless failed DHCP activations (22,292 occurrences over one 31-day boot) — a chronic background tax contributing to the pi0 watchdog crash (issue #22). Marked `cilium*`/`lxc*`/`veth*` unmanaged via a NetworkManager `conf.d` drop-in; applied to source and all 4 live nodes.
- `homekube-main@37013d8`: `argocd-application-controller` OOMKilled 23 times over 31 days on pi1 — its 512Mi limit (set by issue #6 off a July 12 baseline) no longer covered actual usage as the managed-Applications count grew to 18. Raised to 768Mi (requests 128Mi → 192Mi). Root-caused issue #26; a separate historical `argocd-repo-server` OOM pattern on pi2 (pre-issue-#6, no recurrence) was also investigated and closed as resolved. See decision 055.

### Decisions
- [056](DECISIONS.md#056--root-cause-kubelet-memory-leak-issue-40-restart-as-interim-mitigation-upgrade-tracked-separately-2026-08-22): root-caused kubelet memory leak (issue #40) to a known upstream v1.36 regression, fixed in v1.36.3+.
- [055](DECISIONS.md#055--raise-argocd-application-controller-memory-limit-512mi--768mi-2026-08-22): raised argocd-application-controller memory limit, root-causing issue #26's OOM investigation.
- [053](DECISIONS.md#053--fix-prometheus-argocd-app-sealed-grafana-admin-secret--cert-manager-admission-webhook-2026-08-22): sealed Grafana admin secret + cert-manager admission webhook, root-causing the `prometheus` app's stuck sync.

### Operational
- Restarted `kubelet` on pi1/pi2/pi3 to reclaim leaked memory (1483MB/806MB/1439MB → ~50MB each) — interim mitigation for issue #40's kubelet memory leak, pending the v1.36.4 upgrade. All nodes stayed `Ready`, no pods disrupted.
- pi0 (control-plane, sole node) hit its 4th BCM2835 hardware-watchdog reset (issue #22): journal silent from 14:56 AEST, apiserver outage confirmed 16:40 UTC Aug 21 through manual power-cycle ~08:00 AEST Aug 22. No self-recovery; required physical power-cycle. Hermes's concurrent chart stabilization (0.1.1→0.1.8) investigated as a possible trigger and ruled out as direct cause — correctly excluded from pi0 by the control-plane taint. Commented on issue #22 with full timeline (4th occurrence).

## 2026-08-21

### Added
- `homekube-apps@7d17e07`: Hermes tile on Homepage (new `AI` service group, link to `https://192.168.86.246`).

### Fixed
- `herminator@cd67b75`: hermes dashboard served no authentication (`__HERMES_AUTH_REQUIRED__=false`) and chat WebSockets reconnect-looped with code 1006 — the loopback bind (`HERMES_DASHBOARD_HOST=127.0.0.1`) made hermes disable its Dex OAuth gate and apply loopback-only WS Origin rules. Dashboard now binds `0.0.0.0` so the gate engages; nginx got the missing WebSocket upgrade headers and forwards the real Host. Chart 0.1.5.
- `herminator@6cbbd38`: hermes VIP timed out for all tailnet clients — the (since 0.1.4 healthy) tailscale sidecar's policy routing sent pod replies to `100.x` client IPs out its own `tailscale0` instead of back via Cilium (asymmetric return path). `postStart` hook adds an `ip rule` routing pod-CIDR-sourced traffic via the main table. Chart 0.1.6.
- `herminator@e10f5aa` + `herminator@0dcd708`: "Failed to save model assignment" — `config.yaml` was an immutable ConfigMap `subPath` mount while hermes rewrites its config at runtime. Replaced with a seed-once init container copying onto the PVC (guard: seed when missing *or* empty — a 0-byte stub on the PVC initially bricked the rollout). See herminator DECISIONS.md #009. Chart 0.1.7/0.1.8.

## 2026-08-19

### Added
- `homekube-apps@9b5a358`: Hermes registered as a Dex public PKCE static client (`wave-02-apps/dex.yaml`), and a new `hermes` ArgoCD Application (`wave-03-apps/hermes.yaml`, sourcing `jangroth/herminator`'s `chart/`, sync-wave 3) with `ignoreDifferences` on the Tailscale state Secret. Wiring step for herminator Spec 001 (homekube#38). See decision 052.

### Fixed
- `herminator@cbb7c5f`: hermes container crashlooped — Deployment used `command:` instead of `args:`, bypassing the image's ENTRYPOINT dispatcher. Chart bumped to 0.1.1.
- `herminator@4f2c5ed`: hermes dashboard rejected requests with "Invalid Host header" — nginx forwarded the external VIP hostname straight through to the loopback-bound dashboard, tripping its DNS-rebinding guard. Pinned the proxied Host header to the dashboard's own bind address. Chart bumped to 0.1.2.
- `herminator@6018e57` + `herminator@0b4aa23`: hermes tailscale sidecar crashlooped with `invalid key` — the sealed `TS_AUTHKEY` didn't match any key in the tailnet; the first reseal re-encrypted the same stale plaintext. Revoked it and sealed a genuinely new key. Chart 0.1.3/0.1.4.

### Decisions
- [052](DECISIONS.md#052) — Wire up Hermes: Dex static client + ArgoCD Application.

## 2026-07-22

### Added
- `homekube-main@32fdaa3`: CI workflow (`.github/workflows/ansible-lint.yml`) runs `task lint` (ansible-lint) on PRs touching ansible files, mirroring the local lint command.

### Fixed
- `homekube-apps@d8f5d7a`: Grafana had no datasources and all dashboards were empty — the `grafana-sc-datasources`/`grafana-sc-dashboard` sidecars were POSTing their reload webhook over plain HTTP against an HTTPS-only Grafana (since Cap-9), so provisioning files written to disk were never actually loaded. Pointed both `reloadURL`s at HTTPS and set `REQ_SKIP_TLS_VERIFY: "true"`. See decision 051.

### Decisions
- [051](DECISIONS.md#051) — Fix Grafana sidecar reload webhooks for HTTPS.

## 2026-07-21

### Fixed
- `homekube-apps@b1ee1e1`: Loki (`loki-sc-rules`) and Grafana (`grafana-sc-dashboard`/`grafana-sc-datasources`) config-reload sidecars had been CrashLoopBackOff/OOMKilled for ~5 days against the 64Mi memory limit set in issue #9 — raised to 192Mi. See decision 047.
- `homekube-apps@c611c2c`: Alloy's `configReloader.resources` values were misnested under `controller:` (chart expects it top-level) and had been silently ignored by Helm since #9 — moved to top level so the sidecar actually gets its 32Mi/64Mi request/limit. Also raised the main `alloy` container's memory limit 256Mi→384Mi after finding two of four pods running at 80-93% of the old limit. See decision 048.

- `homekube-apps@ea6516d`: Loki's main-container `resources` (1Gi/2Gi memory, 100m/500m CPU) were misnested under the top-level `loki:` key instead of `singleBinary:` (chart has no `resources` field under `loki:` for `deploymentMode: SingleBinary`) — never applied since #9, so `loki-0`'s main container ran with no requests/limits at all. Moved to `singleBinary.resources`. See decision 049.

### Decisions
- [047](DECISIONS.md#047) — Raise `k8s-sidecar` memory limits for Loki/Grafana config-reload sidecars.
- [048](DECISIONS.md#048) — Fix misnested Alloy `configReloader` values key; raise Alloy memory limit.
- [049](DECISIONS.md#049) — Fix misnested Loki `resources` values key.

### Operational
- Applied `homekube-main` PR #9 (Cilium/Hubble resource requests/limits) to the live cluster via `task 40-cni`; verified `cilium-agent`, `cilium-envoy`, `cilium-operator`, `hubble-relay`, and `hubble-ui` (frontend+backend) all show the PR's declared requests/limits. Added corresponding Deployed line item to `README.md` Resource Budget (~1 GiB requests). Note: most init containers on the `cilium` DaemonSet (`config`, `mount-cgroup`, `apply-sysctl-overwrites`, `mount-bpf-fs`, `clean-cilium-state`) remain unbounded — the top-level `resources:` key only reaches the main `cilium-agent` container, narrower than the PR description implies; not addressed here since these are short-lived.

## 2026-07-22

### Operational
- Merged and applied `homekube-main` PR #8 (ArgoCD component resource requests/limits) to the live cluster via `task 50-gitops`; pi0 crashed mid-deployment (BCM2835 watchdog, same pattern as issue #22) and required a manual power-cycle — after re-running the task, verified all 8 declared containers (`application-controller`, `applicationset-controller`, `notifications-controller`, `redis`, `redis` exporter, `repo-server`, `copyutil` init container, `server`) show the PR's exact requests/limits, all 4 nodes `Ready`, and no stuck Helm `pending-upgrade` lock. Added ArgoCD line item to `README.md` Resource Budget (~400 MiB requests). Commented on issue #22 with this third occurrence.

## 2026-07-13

### Changed
- Resource Budget table moved from spec 005 to top-level `README.md` — it's living information that changes as workload requests/limits change, not a point-in-time record (issue #35). Spec 005 §Resource Budget now points at README.
- Consolidated documentation: cluster topology, network/architecture diagrams, and component/version tables moved from `homekube-main/README.md` and `homekube-apps/README.md` into the top-level `README.md` — sub-repo READMEs now hold only content specific to operating that repo (issue #34). Fixed version drift found in the move: Kubernetes `1.34.1`→`1.36.1`, containerd `2.1.4`→`2.3.0`, Cilium `1.18.2`→`1.19.4`, Longhorn `1.9.1`→`1.11.2` (also `CLAUDE.md`), sealed-secrets `2.18.6`→`2.19.1`, metrics-server chart version added (`3.12.2`, previously unlisted).

- Moved `homekube-main/README.md`'s banner image gallery and References/Inspiration section up to the top-level `README.md`; removed its now-empty Overview section (issue #34).

### Removed
- `homekube-main/README.md` Components/Nodes tables and both mermaid diagrams (now in root README); `homekube-apps/README.md` Deployed Components table (now in root README).

## 2026-07-03

### Added
- Homepage dashboard v1.13.2 (spec 007) on LB VIP `192.168.86.245:80` — vendored raw manifests in `wave-03-apps/homepage/` (DECISION-042), open on the VIP without auth (DECISION-043). Widgets: Kubernetes cluster + per-node (metrics-server), Longhorn storage (info widget), open-meteo (Cronulla); ArgoCD service widget via sealed `apiKey` token (`homepage-widget-secrets`); Prometheus targets widget; links for Grafana (DECISION-044), Alertmanager, Dex; repo bookmarks; background image. `homekube-apps@947d554` + follow-ups
- ArgoCD local account `homepage` (`apiKey` capability only) + `role:readonly` RBAC grant in the Ansible Helm values; `crane` added to control-node packages — `homekube-main@b3c96b3`
- `control-node` task codifying homekube-CA browser trust on darth (idempotent; no-ops where already trusted) — `homekube-main@e76299f`
- README (homekube-apps): "Homepage widget credentials (human step)" section — token minting + kubeseal, and the rebuild re-mint/re-seal story; Homepage row in Deployed Components

### Fixed
- Homepage crashloop: `/app/config` is a read-only ConfigMap mount and homepage skeleton-copies missing config files (EROFS) — ship empty `docker.yaml`/`proxmox.yaml`/`custom.css`/`custom.js` (`homekube-apps@fd0fbf8`)
- Longhorn info widget "Missing Longhorn URL" — URL belongs in `settings.yaml` `providers.longhorn`, not the widget entry (`homekube-apps@0beb5a9`)
- Dex icon 404 — no `dex` icon in dashboard-icons/selfh.st; use upstream's glyph logo (`homekube-apps@1bb9a6b`)

### Operational
- Minted ArgoCD API token for the `homepage` account (admin login); sealed into `homepage-widget-secrets`
- Created, then deleted, a Grafana viewer service account after the widget test failed on `/api/admin/stats` (DECISION-044)
- Diagnosed open-meteo widget "API Error" as an upstream outage — `api.open-meteo.com` unreachable from both the pis and darth while general egress was healthy; no config change

### Decisions
- [DECISION-042](DECISIONS.md) — Homepage installed from vendored raw manifests, not a community Helm chart
- [DECISION-043](DECISIONS.md) — Homepage open (no auth) on its LB VIP, plain HTTP; SSO + TLS deferred to the ingress story
- [DECISION-044](DECISIONS.md) — Homepage's Grafana entry is link-only; live widget dropped

---

## 2026-07-02

### Added
- Dex chart 0.24.1 / app 2.44.0 deployed via ArgoCD (`wave-02-apps/dex`); HTTPS on LB VIP `192.168.86.244`; Google OAuth connector via sealed-secret `dex-google-oauth`; static clients for ArgoCD and Grafana
- CoreDNS `hosts` block mapping `pi0.taild13083.ts.net → 192.168.86.244` (in-cluster pods cannot resolve `.ts.net` or reach Tailscale IPs); deployed as `coredns-patch` ArgoCD Application
- `dex-tls` cert-manager Certificate (DNS SAN `pi0.taild13083.ts.net`, issuer `homekube-ca`); Dex mounts it for HTTPS
- `argocd-server-tls` cert-manager Certificate (IP SAN `192.168.86.241`, issuer `homekube-ca`); ArgoCD auto-detects and serves HTTPS
- `grafana-tls` cert-manager Certificate (IP SAN `192.168.86.243`, issuer `homekube-ca`); Grafana self-terminates HTTPS
- ArgoCD OIDC config: `oidc.config` in `argocd-cm` pointing at standalone Dex; `rootCA` = `homekube-ca` PEM; scopes `[email, groups]` for email-based RBAC; policy `g, jan.groth.de@gmail.com, role:admin`
- Grafana `auth.generic_oauth` enabled against Dex; `grafana.ini` `protocol: https`; TLS cert mounted from `grafana-tls` secret
- `argocd-extras` ArgoCD Application now serves HTTPS-only (port 443) on VIP `192.168.86.241`; port 80 removed (DECISION-041)
- Persistent systemd journald (`Storage=persistent`) on all nodes via Ansible `k8s-node` role — enables post-crash log retrieval

### Changed
- ArgoCD Helm values: `dex.enabled: false` (bundled Dex disabled); `server.insecure` removed (HTTPS mode); OIDC + RBAC config moved into `configs.cm` / `configs.rbac` (DECISION-040); `argocd-cm.yaml` and `argocd-rbac-cm.yaml` removed from `argocd-extras`
- `ansible.cfg`: `inject_facts_as_vars = False`; `ansible_hostname` → `ansible_facts['hostname']` in `gitops` and `cni` roles
- Tailscale `serve` on pi0: `tailscale serve --bg --https=443 http://192.168.86.244:5556` bridges browser HTTPS (`.ts.net`) to Dex LB VIP

### Operational
- Cleared Helm pending-upgrade lock (`kubectl -n argocd delete secret -l 'status=pending-upgrade'`) after pi0 watchdog reset during `task 50-gitops`
- Recovered ArgoCD from broken state caused by `configs.cm.create: false` (Helm deleted `argocd-cm`; informer invisible to unlabelled CM); fix: moved config to Helm values with `create: true`

### Decisions
- [DECISION-040](DECISIONS.md) — ArgoCD OIDC + RBAC config owned by Helm, not standalone ArgoCD CMs
- [DECISION-041](DECISIONS.md) — ArgoCD LB service HTTPS-only; port 80 dropped

---
