# Decision Log

---

## 059 — Apply spec 008: S3 backup target + scoped Terraform identity (2026-09-01)

**Area:** cloud

**Decision:** Applied `homekube-main/terraform/bootstrap-identity/` and `homekube-main/terraform/backup-target/` (spec 008), closing issue #20. `bootstrap-identity` created two IAM Identity Center permission sets — `homekube-terraform` (least-privilege, scoped to `homekube-*`-named S3/IAM resources) and `homekube-readonly` (AWS-managed `ReadOnlyAccess`) — plus two attribution-only IAM roles (`homekube-agent-terraform`/`homekube-agent-readonly`) Claude assumes on top of Jan's active SSO session via `sts:AssumeRole`, so CloudTrail can distinguish Claude-attributed actions without granting any standing credential. `backup-target` created the S3 bucket (`bucket_namespace = "account-regional"`, sidestepping classic global-namespace name collisions), a 30-day lifecycle safety net, and IAM user `homekube-backup` with bucket-scoped credentials for Longhorn/Velero (issues #19/#21). Every taggable resource across both stacks carries `Project=homekube` / `Stack=<name>` / `ManagedBy=terraform`.

**Rationale:** Storage class S3 Standard over Standard-IA: at issue #19's 7-day retention, every object is deleted before IA's 30-day minimum-duration charge would even be recouped, so IA's lower nominal rate loses to paying for unused minimum storage plus retrieval fees. Tags were added as a first-class requirement after evaluating resource-identification options for disaster recovery without the state file (deliberately local and gitignored, decision 058) — tags cover permission sets, IAM roles/user, and the S3 bucket, but `aws_ssoadmin_account_assignment`, inline-policy, and access-key resources don't support tagging at all (confirmed via `terraform providers schema -json`), so the `homekube-*` naming convention remains the primary identification mechanism for those.

**Trade-offs accepted:** IAM Identity Center doesn't auto-provision permission-set inline-policy edits to already-assigned accounts — discovered via repeated `AccessDenied` errors on `backup-target`'s first apply, each one only clearing after an explicit `aws sso-admin provision-permission-set` call. Every future edit to `homekube-terraform`'s policy needs that same manual step; not worth automating via a `null_resource` trigger for this apply cadence yet. Longhorn/Velero authenticate to S3 with a static IAM access key rather than a federated identity — the cluster is bare-metal off-AWS, so IRSA/OIDC-style federation would require standing up and publicly exposing a self-hosted OIDC provider, disproportionate for a single-operator homelab; mitigated by scoping the IAM policy to the bucket ARN only, no `s3:*`.

---

## 058 — Adopt Terraform for AWS/cloud-account-level infrastructure (2026-08-24)

**Area:** cloud

**Decision:** Terraform becomes the standard tool for infrastructure that lives in an AWS account rather than on the Pi cluster itself, starting with spec 008 (S3 backup bucket + IAM user, issue #20). Committed under `homekube-main/terraform/<resource>/`, one subdirectory per logical resource group, state local and gitignored, applied by hand rather than automated — these are rare, high-blast-radius changes that need a human AWS identity to bootstrap from. Terraform's ownership stops at the AWS/cloud boundary: Ansible still owns the Pi fleet, ArgoCD still owns in-cluster resources.

**Rationale:** Ansible provisions the physical fleet and ArgoCD reconciles in-cluster manifests, but neither reaches AWS-account-level resources — spec 008 hit that gap directly. Considered and rejected as a blanket policy, not just for the one bucket: Crossplane, which would run an AWS-provider controller in-cluster indefinitely and need its own sealed AWS credentials for what's likely to stay a handful of rarely-changed resources — wrong weight class, and it recreates the secret-bootstrapping problem this decision exists to avoid; ad-hoc `aws` CLI scripts, versioned but with no state tracking, drift detection, or `destroy`; and manual console changes, which violate "source reflects runtime" outright. Terraform's footprint at this project's scale is small — a local binary, no server component, gitignored state — so the cost of a second IaC tool in the repo is low relative to what it buys: every future AWS resource gets provisioned the same reproducible way instead of a fresh judgment call each time.

**Trade-offs accepted:** Local Terraform state is the source of truth for AWS resources and lives only on the operator's machine (darth) — no remote backend, so if that machine's state is lost, resources need re-import rather than re-apply. Acceptable for a single-operator homelab with a small, slow-changing resource set; revisit if the AWS footprint grows enough to justify a remote backend. This also commits future AWS-facing work to Terraform by default — a resource whose shape genuinely fits Crossplane's reconciliation model better would need its own explicit exception, not a silent drift back to console/CLI.

**Addendum (2026-09-01):** `bootstrap-identity` applied as designed — see decision 059 for the final permission-set scope and attribution-role design as actually run (not just the spec draft).

---

## 057 — Route severity=info alerts to null receiver instead of disabling or resizing (2026-08-23)

**Area:** observability

**Decision:** Added a `severity=info` sub-route to the `null` receiver in the alertmanager config (`homekube-apps/applications/wave-01-apps/kube-prometheus.yaml`, `homekube-apps@ba50b7b`). Closes issue #3.

**Rationale:** Issue #3 was unscoped — "the alert rule set needs review" with no specific rule identified. Queried the live cluster (`/api/v1/alerts`, `/api/v2/silences`) rather than guessing: 7 alerts active, 5 of them `CPUThrottlingHigh` (severity=info) firing continuously across all 4 node-exporter pods plus the grafana-sc-dashboard sidecar since 2026-08-21/22; `Watchdog` and `InfoInhibitor` (severity=none) accounted for the rest and are expected/by-design; zero silences configured. `CPUThrottlingHigh` compares usage against CPU *limits*, and node-exporter (100m) / grafana sidecar (50m) limits are deliberately tight for the Pi-scale resource budget, so brief bursts trip it constantly with no actual degradation. The alertmanager route had no severity split, so this info-level noise went to Telegram same as anything critical. Chose severity-based routing over the two alternatives considered: disabling the rule outright (matches the existing `defaultRules.disabled: KubeProxyDown` pattern but loses the signal from Grafana/Prometheus entirely) or raising the CPU limits (spends real budget on a constrained cluster to silence a rule that's arguably miscalibrated for this scale, not fixing anything real). Routing preserves the rule's value as a Grafana/Prometheus signal while stopping the page.

**Trade-offs accepted:** Any future genuinely-informational alert tagged `severity=info` will also route to `null` rather than Telegram — acceptable since the whole point is that info-severity was never meant to page; anything actionable should be tagged at a higher severity.

---

## 056 — Root-cause kubelet memory leak (issue #40); restart as interim mitigation, upgrade tracked separately (2026-08-22)

**Area:** platform-engineering

**Decision:** Root-caused issue #40 (kubelet ~1.47Gi RSS on pi1) as a known upstream kubelet regression, not a config issue. Restarted `kubelet` on pi1/pi2/pi3 live (`systemctl restart kubelet`) to reclaim memory immediately; verified all nodes stayed `Ready` and no pods were disrupted. Opened a follow-up issue to bump `kubernetes_version` (`homekube-main/ansible/group_vars/all.yml`) 1.36.1 → 1.36.4, which is the actual fix.

**Rationale:** `ps` RSS was corroborated against the kubelet cgroup's `memory.current`/`memory.stat` (`anon` matched RSS almost exactly), ruling out a `ps` measurement artifact. Comparing `MemoryCurrent` against each node's `ActiveEnterTimestamp` across all 4 nodes showed a near-uniform ~22 MB/day growth rate independent of each node's pod count (pi1: 65d/1483MB/22.8 MB/day; pi2: 37d/806MB/21.8 MB/day; pi3: 65d/1439MB/22.1 MB/day; pi0 freshly restarted at 112MB) — a signature pointing at a time-based leak in kubelet itself rather than per-pod overhead. This matches [kubernetes/kubernetes#139823](https://github.com/kubernetes/kubernetes/issues/139823): a `context.cancelCtx` leaked on every `startPodSync` in kubelet, introduced as a v1.36 regression, fixed and backported into the `release-1.36` branch, first shipped in v1.36.3 (2026-07-23). This cluster runs v1.36.1, predating the fix. The upgrade is scoped as a separate issue rather than done inline here since it touches kubelet/kubeadm/kubectl versions across all 4 live nodes and warrants its own rollout plan, not a same-session change.

**Trade-offs accepted:** The leak will resume at ~22 MB/day on pi1/pi2/pi3 until the version bump lands — acceptable short-term given decision 055 already gave pi1 headroom, and pre-restart levels (~1.4-1.5Gi) took ~2 months to accumulate.

---

## 055 — Raise argocd-application-controller memory limit 512Mi → 768Mi (2026-08-22)

**Area:** platform-engineering

**Decision:** Raised `controller.resources` in `argocd-helm-values.yaml` (`homekube-main@37013d8`): requests 128Mi → 192Mi, limits 512Mi → 768Mi. Applied live via `task 50-gitops`. Closes issue #26.

**Rationale:** Issue #26 asked to root-cause a historical OOM; investigation via `journalctl -k` (sudo already works fine — the issue's "blocked on group membership" note was stale) found two distinct patterns. First, `argocd-repo-server` OOM'd ~1900 times on pi2 between 2026-07-16 and 2026-07-21 — pre-dates issue #6 (no resource limits existed on any ArgoCD container before that fix landed 2026-07-21); resolved, no recurrence since. Second, `argocd-application-controller` on pi1 was still actively OOMKilled (23 restarts over 31 days, including same-morning bursts) — issue #6 had sized its 512Mi limit off a 2026-07-12 baseline; usage has since grown with the managed-Applications count (18) and now sits ~290–413Mi baseline with bursts landing right at the 512Mi ceiling (one kill was `usage 524304kB` vs `limit 524288kB`, 16kB over). pi1's broader memory budget (2358Mi/8153Mi requested = 29%, ~3.2Gi available) had comfortable room to absorb the increase.

**Trade-offs accepted:** Aggregate memory *limits* on pi1 move further into overcommit (already 85% of node capacity pre-change) — fine as long as pods don't all burst simultaneously, which they haven't. A secondary anomaly surfaced during investigation — kubelet itself running ~1.47Gi RSS on pi1, well above a normal footprint — was intentionally left uninvestigated; it's unrelated to the ArgoCD OOM pattern and may warrant its own issue.

---

## 054 — Raise systemd runtime watchdog timeout 1min → 10min; downgrade issue #22 with an exit criterion (2026-08-22)

**Area:** platform-engineering

**Decision:** Override the Raspberry Pi OS vendor watchdog drop-in (`/usr/lib/systemd/system.conf.d/40-rpi-enable-watchdog.conf`, `RuntimeWatchdogSec=1m`) with an Ansible-managed `/etc/systemd/system.conf.d/50-homekube-watchdog.conf` setting `RuntimeWatchdogSec=10min`, deployed by a new `configure_watchdog.yml` task in the `k8s-node` role (`homekube-main@d965291`) and applied live to all 4 nodes. Downgraded issue #22 `blocker` → `degraded` with an explicit exit criterion (no watchdog reset through ~2026-10-03 incl. ≥2 Helm rollouts → close), and split the node-lifecycle taint side finding into its own issue (#39).

**Rationale:** All four watchdog crashes were transient load stalls that tripped the vendor's 60-second deadline, and the resulting hardware reset **never self-recovered a node** — every occurrence ended in a manual power-cycle. So the fast timeout delivered zero recovery value while converting recoverable stalls into hard crashes; its cost/benefit was strictly negative in practice. Raising it is safe because sysfs reports `max_timeout: 0`: the kernel watchdog core pets the BCM2835 itself beyond the chip's short hardware window and enforces the userspace timeout in software, so a 10-minute setting still guards genuine kernel/systemd hangs. 10min over 5min because the 4th occurrence showed stall windows can run long, and per above there's no recovery benefit to firing early. The exit criterion exists so the issue doesn't linger as an unfalsifiable investigation: for this cluster, "the 1-minute vendor timeout was the operative bug" is an acceptable conclusion if the trigger profile (Helm-churn rollouts) stops producing resets.

**Trade-offs accepted:** A genuinely hung node now takes up to 10 minutes to hardware-reset instead of 1 (moot in practice — observed resets ended in a hang requiring manual power-cycle anyway). The deeper root-cause threads (reboot-hang via `reboot=w`, load-stall mechanism, contradictory `cgroup_disable=memory`/`cgroup_enable=memory` cmdline flags) intentionally close with #22 if the exit criterion is met, unproven.

---

## 053 — Fix prometheus ArgoCD app: sealed Grafana admin secret + cert-manager admission webhook (2026-08-22)

**Area:** observability

**Decision:** Two independent fixes to `homekube-apps/applications/wave-01-apps/kube-prometheus.yaml`, both committed and pushed (`homekube-apps@83fc330` + prior commit):
1. Set `grafana.admin.existingSecret: prometheus-grafana-admin`, pointing at a new sealed secret (`applications/wave-01-apps/prometheus-extras/prometheus-grafana-admin.yaml`, following the existing `alertmanager-telegram`/`dex-google-oauth` sealed-secrets pattern) carrying the previously-live Grafana admin credentials.
2. Set `prometheusOperator.admissionWebhooks.certManager.enabled: true` (no `issuerRef` — chart's own self-signed root, internal-only cert, not tied to `homekube-ca`).

**Rationale:** The `prometheus` Application had been stuck `OutOfSync`/`Sync failed` since 2026-07-22. Root cause of (1): kube-prometheus-stack's Grafana admin-password helper uses Helm's `lookup` function to reuse the existing password across reconciles, but `lookup` only works against a live cluster during `helm install/upgrade` — ArgoCD renders via `helm template`, where `lookup` always returns nil, so **every** reconcile generated a fresh random password. That perpetually diffed the `prometheus-grafana` Secret and (via its `checksum/secret` pod annotation) the Grafana Deployment, and `selfHeal: true` kept re-triggering syncs to "fix" the fake drift. Root cause of (2): the rapid re-sync cadence from (1) raced the chart's default Job-based webhook-cert PreSync hook (`prometheus-kube-prometheus-admission-create`, `hook-delete-policy: before-hook-creation,hook-succeeded`) — the Job always completed successfully (confirmed via `kubectl get events`, three separate runs all reaching `Completed`), but self-deleted immediately on success, and ArgoCD's own post-hook status poll then found it "missing" and marked the whole sync `Failed` after exhausting all 5 retries. This is a known ArgoCD/Helm-hook race, not something the Job itself was doing wrong. Switching to cert-manager removes the Job/hook mechanism from the chart's render entirely — cert-manager issues the webhook TLS chain (self-signed Issuer → root-cert Certificate → root Issuer → admission Certificate) as plain reconciled resources instead, so there's nothing left to race.

**Trade-offs accepted:** One-time Grafana Deployment rolling restart (env source changed from the old Helm-rendered secret to the new sealed one) and one-time prometheus-operator pod restart (the new pod briefly `CrashLoopBackOff`'d on `/cert/tls.crt: no such file` because it started before cert-manager finished issuing the admission cert on the very first sync — self-resolved on the pod's next backoff retry, manually nudged with a pod delete to confirm immediately rather than wait it out). Both one-off transients, not recurring behavior. Verified `prometheus` Application converges to `Synced`/`Healthy` with no `SyncError` condition after push.

---

## 052 — Wire up Hermes: Dex static client + ArgoCD Application (2026-08-19)

**Area:** identity

**Decision:** Added a `hermes` static client (`id: hermes`, `public: true`, no `secret:` field — public PKCE client) to `homekube-apps/applications/wave-02-apps/dex.yaml`'s `staticClients`, and a new `homekube-apps/applications/wave-03-apps/hermes.yaml` ArgoCD `Application` sourcing `jangroth/herminator`'s `chart/` directly as a git-repo Helm chart (`homekube-apps@9b5a358`). Sync-wave `"3"` (alongside Homepage, after Dex), `automated: {prune: true, selfHeal: true}`, `CreateNamespace=true`, with an `ignoreDifferences` entry on the `hermes-tailscale-state` Secret's `/data` so ArgoCD's selfHeal doesn't fight tailscaled's runtime writes to its own state. Registered in `applications/kustomization.yaml`; `homekube-apps/CLAUDE.md`'s wave table updated to match.

**Rationale:** Wiring step for [herminator Spec 001](https://github.com/jangroth/herminator/blob/main/docs/specs/001-deploy-hermes-to-homekube.md) (tracked as [homekube#38](https://github.com/jangroth/homekube/issues/38)) — herminator's chart was already built, validated, and pushed with real credentials sealed in-repo (`herminator@a4266cd`); this is the remaining `homekube-apps`-side half. The Dex client follows the existing `staticClients` pattern used by `argocd`/`grafana`, but with `public: true` instead of a `secret:` field, since hermes's self-hosted OIDC is a public PKCE client with no client secret at all. The issue explicitly excluded this from `agent-safe` — it touches Dex's auth-adjacent config and creates a new auto-sync Application — so it got a human review pass (via plan mode) before committing, per this repo's trust model.

**Trade-offs accepted:** This decision documents the manifest changes as committed; the actual cluster rollout (root app → `dex` → `hermes`, cascading via each Application's `automated` sync) only happens once `homekube-apps` is pushed. The end-to-end acceptance walkthrough (OIDC login flow, shields-up check, PVC persistence) from Spec 001 is deferred to that point — this entry covers the wiring, not verified-live status.

---

## 051 — Fix Grafana sidecar reload webhooks for HTTPS (2026-07-22)

**Area:** observability

**Decision:** In `homekube-apps/applications/wave-01-apps/kube-prometheus.yaml`, set `grafana.sidecar.datasources.reloadURL` and `grafana.sidecar.dashboards.reloadURL` to `https://localhost:3000/...` (from the chart default `http://localhost:3000/...`), and added `REQ_SKIP_TLS_VERIFY: "true"` to each sidecar's `env` (`homekube-apps@d8f5d7a`).

**Rationale:** Reported symptom: Grafana had no datasources and every dashboard was empty. Investigation found the `prometheus-kube-prometheus-grafana-datasource` ConfigMap and all dashboard JSONs were correctly written to `/etc/grafana/provisioning/...` inside the pod, and `kubectl exec`-ing a manual `POST /api/admin/provisioning/datasources/reload` immediately populated all three datasources (Prometheus, Alertmanager, Loki) and every dashboard — proving the GitOps config and connectivity were fine. Root cause: Grafana has been HTTPS-only since Cap-9 (`5ec145c`, "Grafana TLS + OIDC via Dex"), but the `grafana-sc-datasources`/`grafana-sc-dashboard` sidecars still call their reload webhook over plain HTTP — the call fails to connect, so newly-written provisioning files are never picked up. Follow-up TLS fixes after Cap-9 (health probes, OIDC `redirect_uri`, TargetDown alert scrape) all missed this webhook. `REQ_SKIP_TLS_VERIFY` is a separate flag from the chart's `sidecar.skipTlsVerify` (which only covers kube-apiserver calls) — confirmed against `kiwigrid/k8s-sidecar` source that it's required for the reload call itself, since Grafana's cert is issued for the external VIP, not `localhost`.

**Trade-offs accepted:** None — the fix only affects the sidecar-to-Grafana reload call; no application config changed. Applies to the live cluster on next ArgoCD sync (`selfHeal: true`); already applied manually to the running pod via the same API calls used to diagnose it, so Grafana is not currently missing data while the fix propagates.

---

## 050 — Ansible lint runs in CI on PRs, not gated into every local task (2026-07-22)

**Area:** process

**Decision:** Added `homekube-main/.github/workflows/ansible-lint.yml`, triggered on PRs touching `ansible/**`, `Taskfile.yml`, `.ansible-lint`, `.yamllint`, `pyproject.toml`, or `uv.lock`. It installs `uv` and `task`, then runs `task setup` + `task lint` — the same commands used locally — rather than reimplementing the ansible-lint invocation directly in the workflow. `task lint` itself stays a separate, opt-in step; it is not made a dependency of the other Taskfile tasks (e.g. the `NN-*` playbook runners).

**Rationale:** Running the exact `task lint` command in CI (vs. a bespoke `uv run ansible-lint ...` step) keeps local and CI lint in lockstep — a Taskfile change automatically applies to both without touching the workflow. Not gating lint into every local task was a deliberate choice: those tasks are often run mid-edit against a single playbook, and forcing a full lint pass first would slow down iteration for marginal benefit; CI is the actual enforcement point for anything landing in a PR.

**Trade-offs accepted:** No local nudge before commit beyond developer discipline — a pre-commit/pre-push git hook was suggested as a lighter-weight alternative if that becomes a problem, but not implemented.

---

## 049 — Fix misnested Loki `resources` values key (2026-07-21)

**Area:** observability

**Decision:** In `homekube-apps/applications/wave-01-apps/loki.yaml`, moved `resources` (1Gi/100m request, 2Gi/500m limit) from under the top-level `loki:` key to `singleBinary:` — the `grafana/loki` chart (v7.0.0) has no `resources` field under `loki:` (that key is app config only: schema, storage, limits_config, etc.); for `deploymentMode: SingleBinary` the container resources live under `singleBinary.resources` (confirmed via `helm show values grafana/loki --version 7.0.0`).

**Rationale:** Same class of bug as decision 048 (Alloy's misnested `configReloader`), found while investigating a report that `loki-0`'s main container was reading way over its memory/CPU limits. `kubectl get pod loki-0 -o jsonpath` showed the `loki` container with **empty** `resources` — no requests, no limits — confirming the intended 1Gi/2Gi memory and 100m/500m CPU values from #9 had never actually applied. Actual usage (`kubectl top`: ~317Mi / 18m) is well within the intended limits; the "way above limits" reading was an artifact of tools (k9s) computing %-of-limit against a limit of zero/absent, not genuine overconsumption. ArgoCD reported the `loki` app `Synced`/`Healthy` throughout, same blind spot as #048 — the rendered manifest matched the (wrong) input values, so sync status alone doesn't catch a misnested Helm key.

**Trade-offs accepted:** None — straightforward key relocation, values unchanged. Worth auditing the remaining charts in this repo (kube-prometheus-stack, alloy already checked) for the same misnesting pattern, since it's evidently easy to get wrong per-chart.

---

## 048 — Fix misnested Alloy `configReloader` values key; raise Alloy memory limit (2026-07-21)

**Area:** observability

**Decision:** In `homekube-apps/applications/wave-01-apps/alloy.yaml`, moved `configReloader.resources` from under `controller:` to the top level (the `grafana/alloy` chart v1.8.1 expects `configReloader` as a top-level key), and raised the main `alloy` container's memory limit from 256Mi to 384Mi.

**Rationale:** While investigating the Loki/Grafana sidecar OOM fix (decision 047), noticed via `kubectl top` and k9s that two of the four Alloy pods were running at 80-93% of their 256Mi memory limit — not yet crash-looping, but close enough that a log-volume spike could tip them into OOMKill. While sizing the fix, found that the `configReloader.resources` block added in commit `4732e0e` (#9) was nested under `controller:`, which isn't where the chart looks for it (`helm show values grafana/alloy --version 1.8.1` confirms `configReloader` is a top-level key) — Helm silently ignored the whole block. The `config-reloader` sidecar has been running on the chart's unbounded default (50Mi request, no limit) rather than the intended 32Mi/64Mi ever since #9, undetected because ArgoCD reported the app `Synced`/`Healthy` (the rendered manifest matched the live state — the bug was in the input values, not a sync failure).

**Trade-offs accepted:** 384Mi is sized for headroom, not measured against Alloy's actual peak — if log volume keeps growing this may need another bump later. Same class of risk as decision 047: a generous limit, not a proven ceiling.

---

## 047 — Raise `k8s-sidecar` memory limits for Loki/Grafana config-reload sidecars (2026-07-21)

**Area:** observability

**Decision:** Raised memory requests/limits for the three `kiwigrid/k8s-sidecar` containers (`loki-sc-rules`, `grafana-sc-dashboard`, `grafana-sc-datasources`) from `32Mi/64Mi` to `64Mi/192Mi` in `homekube-apps/applications/wave-01-apps/{loki,kube-prometheus}.yaml`. README Resource Budget table (issue #9 rows) updated to match.

**Rationale:** Both sidecars had been silently CrashLoopBackOff-ing for ~5 days (`loki-sc-rules`: 1087 restarts; `grafana-sc-dashboard`/`grafana-sc-datasources`: ~199 restarts each), all OOMKilled (exit 137) against the 64Mi limit set in issue #9 (commit `4732e0e`, 2026-07-13) — the crash-loop start times line up almost exactly with that rollout. Root cause: these sidecars run `METHOD=WATCH` with `RESOURCE=both` (configmaps+secrets), cluster-wide — the watch cache grows past the fresh-restart baseline (~32-34Mi observed via `kubectl top`) until it exceeds 64Mi and gets killed, then repeats. The 64Mi budget from #9 didn't account for this steady-state growth. Cluster has ~20 GiB of headroom, so there's no cost pressure to keep these tight.

**Trade-offs accepted:** 192Mi is a generous limit chosen for headroom rather than a measured ceiling — if the underlying cause is an actual unbounded memory leak in `k8s-sidecar` (known behavior in some versions under `RESOURCE=both` + `NAMESPACE=ALL`) rather than a one-time cache-fill, this only delays the next OOM rather than fixing it. Worth revisiting if these containers start crash-looping again at the new limit.

---

## 046 — Nightly automated routines open PRs for `agent-safe` issues, one routine per target repo (2026-07-12)

**Area:** process

**Decision:** Two scheduled Claude Code routines (RemoteTrigger) run nightly: `homekube-apps - nightly agent-safe issue` (2am Sydney) and `homekube-main - nightly agent-safe issue` (midnight Sydney). Each fetches open issues from the `jangroth/homekube` tracker labelled `agent-safe` + its own `repo:*` label, skips issues already in flight, picks one at random, implements it, and opens a PR for human review — never auto-merge.

**Rationale:** Pattern reused from `jangroth/dotfiles`' existing nightly routine, adapted for homekube's multi-repo shape: the issue tracker (`jangroth/homekube`) is a different repo than where most fixes land (`homekube-apps`, `homekube-main`), so each routine's PR-target repo must be sourced explicitly and filtered by `repo:*` rather than assumed to match the tracker. Split into two routines (not one) because the two repos need different sanity checks before opening a PR — `kustomize build applications/` for `homekube-apps`; `ansible-playbook --syntax-check` for `homekube-main`, with no live pi access from the remote environment (no real playbook runs). Both routines currently reuse the existing dotfiles remote environment (`env_01Pq2AjWCXUsSwoC2DNrS8wX`) rather than a dedicated one, since environment creation is UI-only and out of tool reach.

**Trade-offs accepted:** Sharing the dotfiles environment mixes a low-stakes personal-dotfiles trust domain with homekube's production-cluster trust domain (broader GitHub credential scope than either routine strictly needs). Flagged as worth splitting into a dedicated environment later if it causes friction, but not blocking for now.

---

## 045 — GitHub Issues on `jangroth/homekube` replaces `TODO.md`/`open-todos.md` as the single task tracker (2026-07-12)

**Area:** process

**Decision:** All open work items (from `TODO.md`'s Backlog, closed specs' deferred items, and externally-collected TODOs) were migrated to GitHub Issues on `jangroth/homekube` — the single tracker across all three repos (`homekube`, `homekube-main`, `homekube-apps`), rather than per-repo trackers. `TODO.md` and the staging file `open-todos.md` are both deleted; `CLAUDE.md`'s Working Approach now points at Issues. Every issue carries `area:*` (component, reusing `homekube-apps`' existing taxonomy), one of `criticality:blocker`/`degraded`/`polish` (workload-readiness impact — blocker = blocks trusting the cluster with other workloads, degraded = capability exists but not fully trustworthy, polish = doesn't affect workload-readiness), and where applicable `repo:*` (which repo the fix actually lands in) and `agent-safe`.

**Rationale:** A single tracker avoids juggling three separate issue lists for a project that's really one system split across repos for deployment reasons. `repo:*` was added as a second label alongside `area:*` after discovering the two don't reliably correlate: several `area:workload` resource-limit issues initially assumed to target `homekube-apps` (Cilium/Hubble, ArgoCD) actually land in `homekube-main`, because those components are installed directly via Ansible/Helm rather than as ArgoCD-managed apps — `area:*` describes *what*, `repo:*` had to be independently verified against each fix's actual file location, not inferred from the area. `agent-safe` reuses the exact term and PR-only convention already established in `jangroth/dotfiles`, defined by four criteria: no open design decision, no destructive/irreversible live action, no physical or external-account step, and lands as a PR (never a direct push) — chosen for consistency across projects and to keep the global "never push without approval" rule intact even under automation.

**Trade-offs accepted:** `TODO.md`'s Phase 0–5 completion history was deleted rather than archived — judged fully redundant with the already-closed specs (001, 003, 004, 005) and existing `DECISIONS.md`/`CHANGELOG.md` entries, and still recoverable via git history if needed.

---

## 044 — Homepage's Grafana entry is link-only; live widget dropped (2026-07-03)

**Area:** workload

**Decision:** Grafana appears on the Homepage dashboard (spec 007) as a plain link with no live widget. The Grafana service account minted for it was deleted; `homepage-widget-secrets` carries only the ArgoCD token.

**Rationale:** Homepage's Grafana widget authenticates with basic auth only and *unconditionally* fetches `/api/admin/stats` for its dashboard/datasource counts — an endpoint that requires Grafana **server-admin**. Verified empirically: a Viewer service-account token works as basic auth (`api_key:<token>`, 200 on `/api/search` and alerts endpoints) but gets 403 on `admin/stats`, and the widget component renders an error state on any stats failure with no `fields` option to skip the call (checked `widget.js` / `component.jsx` / `use-widget-api.js` at v1.13.2). The only working credentials would be server-admin — unacceptable in the pod env of an unauthenticated dashboard, and the admin-password variant would additionally break when the cap-9 follow-up disables Grafana local auth.

**Trade-offs accepted:** No dashboard/alert counts on the Grafana card. The Prometheus widget covers live monitoring status.

---

## 043 — Homepage is open (no auth) on its LB VIP, plain HTTP; SSO + TLS deferred to the ingress story (2026-07-03)

**Area:** workload

**Decision:** The Homepage dashboard serves unauthenticated HTTP on LB VIP `192.168.86.245`. No login, no TLS.

**Rationale:** Homepage ships no authentication and is not an OIDC client, so it cannot join the cap-9 Dex federation directly; fronting it with oauth2-proxy/forward-auth builds bespoke plumbing the deferred ingress/Gateway-API story would replace wholesale. The VIP is reachable only over Tailscale (and the home Wi-Fi path that is slated for removal) — never public — and the dashboard exposes only read-only status already visible to anyone on the tailnet. Same pre-ingress posture Grafana had in cap-8. Its widget backend tokens are read-only and server-side (never sent to the browser).

**Trade-offs accepted:** Anyone on the tailnet/LAN sees cluster status without logging in, and the browser shows "not secure". Revisit when ingress lands (TLS + forward-auth in one move).

---

## 042 — Homepage installed from vendored raw manifests, not a community Helm chart (2026-07-03)

**Area:** workload

**Decision:** Homepage (spec 007) is deployed from hand-maintained manifests in `applications/wave-03-apps/homepage/` (ArgoCD Application with a single git source), pinning the official image `ghcr.io/gethomepage/homepage`. No Helm chart.

**Rationale:** Upstream ships no official chart and labels the community ones "unofficial". Both candidates (`jameswynn/homepage`, `M0NsTeRRR`) are single-maintainer, low-activity repos with unresponsive issue trackers — a poor dependency for the cluster's front door. Homepage's config *is* a set of YAML files, so a manifest directory holding them verbatim (ConfigMap) is more direct than reverse-engineering chart values; the only real dependency is the official multi-arch image. ArgoCD syncs a plain manifest directory as readily as a chart.

**Trade-offs accepted:** We own the manifests: image bumps, probe paths, and upstream config-layout changes (e.g. the read-only-mount skeleton-copy behaviour, the providers-vs-widget URL split) are ours to track by hand instead of arriving via chart updates. Diverges from the repo's chart-based app pattern — deliberately, and documented in the spec.

---

## 041 — ArgoCD LB service HTTPS-only; port 80 dropped (2026-07-02)

**Area:** security

**Decision:** The `cst-argocd-server` LoadBalancer service exposes only port 443 (→ pod port 8080). Port 80 is not exposed.

**Rationale:** ArgoCD is a Tailscale-only service — all access is via an explicit bookmark or CLI over the tailnet. An HTTP redirect on port 80 adds surface with no benefit; dropping it enforces HTTPS without relying on a redirect.

**Trade-offs accepted:** Anyone who types `http://192.168.86.241` gets a connection refused rather than a helpful redirect. Acceptable — this is an operator tool, not a public-facing page.

---

## 040 — ArgoCD OIDC + RBAC config owned by Helm, not standalone ArgoCD CMs (2026-07-02)

**Area:** identity

**Decision:** `url`, `oidc.config`, and RBAC policy are configured under `configs.cm` / `configs.rbac` in `argocd-helm-values.yaml` (Helm owns `argocd-cm` and `argocd-rbac-cm`). The standalone `argocd-cm.yaml` and `argocd-rbac-cm.yaml` files previously in `argocd-extras/` are removed.

**Rationale:** When both Helm and an ArgoCD Application (via `argocd-extras`) apply to the same ConfigMaps, Kubernetes Server-Side Apply records two competing field managers. On the next Helm upgrade, the conflict surfaces as a fatal error blocking the release. Additionally, ArgoCD's settings informer only caches ConfigMaps that carry the `app.kubernetes.io/part-of: argocd` label — a manually-applied CM without that label is invisible to the informer, causing a "configmap argocd-cm not found" crash loop even though the CM exists. Making Helm the sole owner avoids both problems: Helm adds the required labels automatically and there are no competing managers.

**Trade-offs accepted:** OIDC config (including the `homekube-ca` root CA PEM) lives in the Helm values file rather than in a dedicated Kubernetes manifest. The CA cert is not a secret (public cert), and the OIDC client secret is a literal shared string between ArgoCD and Dex (`argocd-dex-client-secret`) — not a high-value credential. If this becomes a concern, ArgoCD's `$secret:key` reference syntax can be adopted later to pull the client secret from a SealedSecret.

---

## 039 — Dex OIDC callback uses Tailscale MagicDNS (`.ts.net`), not an IP or `piN` host (2026-07-01)

**Area:** identity

**Decision:** For spec 005 cap-9 (Identity & SSO), the Dex OIDC issuer/callback is served on the node's Tailscale MagicDNS name — `https://pi0.<tailnet>.ts.net/dex/callback` — rather than the `https://piN:PORT` scheme originally written into the spec, or the LB VIP IP. Dex itself is exposed on LB VIP `192.168.86.244` for in-cluster/VIP reach; only the browser-facing issuer/callback uses the `.ts.net` name. In-cluster clients (ArgoCD, Grafana) reach Dex by ClusterIP.

**Rationale:** Google OAuth rejects redirect URIs that are raw IP literals (`192.168.86.244`) or non-public-domain hostnames (`pi0`) at client-registration time — only real public domains or `localhost` over HTTPS are accepted. Only Dex's callback is ever registered with Google (Dex is the sole Google OAuth client; ArgoCD/Grafana federate through Dex, not Google directly), so the constraint lands on exactly one URL, but that URL must be a public domain. `.ts.net` is a public domain Google accepts, already resolves for `darth` over the existing Tailscale management plane, and Tailscale can issue a genuine Let's Encrypt cert for it — so the Google-facing leg needs no `homekube-ca` trust. This is materially cleaner than owning/registering a domain or the hosts-file workaround, and it partially pulls "DNS" forward from the Deferred list without committing to the full in-cluster DNS + Gateway API story.

**Trade-offs accepted:** OIDC config is now coupled to the Tailscale tenancy (the `.ts.net` name is per-node and per-tailnet); if the cluster ever leaves Tailscale or real DNS lands, the callback URLs get rewritten. Acceptable — it's the same churn the deferred-DNS note already anticipated, and it removes a hard blocker (Google refusing the redirect URI) that would otherwise stall cap-9 entirely.

---
