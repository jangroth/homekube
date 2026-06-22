# Spec 006 — Cilium-native LoadBalancer (replace MetalLB)

**Status:** Done (executed 2026-06-22)
**Supersedes:** the MetalLB approach in spec 005 capability 4
**Related decisions:** DECISION-031 (this change), DECISION-030 (the conflict that motivates it), DECISION-019 (Wi-Fi subnet choice — still holds)

> This spec is written to be executed in a **later session, potentially by a different model**.
> It is self-contained: it states the current state, the target state, every file to touch,
> the exact cutover order, validation, and rollback. Do not assume context beyond this file,
> `DECISIONS.md` 019/030/031, and the live cluster.

---

## 1. Problem

`type: LoadBalancer` IPs are **not reachable** today, even though spec 005 capability 4 was
optimistically marked complete. MetalLB 0.16.0 announces the pool `192.168.86.241–251` correctly
on `wlan0` (ARP resolves VIP → correct node MAC), but traffic is dropped:

- Cilium runs `kubeProxyReplacement: true` with `devices: "eth0"`. Its eBPF DNAT programs are
  attached only to the wired switch interface. Traffic arriving on `wlan0` (the MetalLB L2 subnet)
  is never DNAT'd to a pod backend, so it is dropped.
- Adding `wlan0` to Cilium `devices` (`eth0,wlan0`) was tried and reverted (DECISION-030):
  Cilium, as a native device manager on `wlan0`, probes MetalLB's VIPs as kernel neighbors
  (`ip neigh`). MetalLB answers ARP via raw sockets, not the kernel stack, so the probe fails,
  the kernel marks the VIP `FAILED`, and Cilium drops forwarded traffic for it. Intermittent —
  breaks once the first successful ARP entry ages out.

Net effect: NodePort is the only working external access path.

## 2. Decision (why Cilium-native)

Drop MetalLB. Use **Cilium's built-in LB-IPAM + L2 announcements** (Cilium 1.19.4 already installed).
Cilium then owns the VIP end-to-end: the same IP is a known *service* VIP in its datapath, not a
remote L3 neighbor to forward to. Traffic on `wlan0` is DNAT'd at eBPF ingress to a pod backend —
there is no "forward to neighbor" step, so **the DECISION-030 `FAILED`-neighbor mechanism cannot
occur**. The announcer and the DNAT engine are the same component and agree about what the VIP is.

This is the only option that **keeps Cilium's eBPF kube-proxy replacement AND preserves direct
home-Wi-Fi access** (pool stays on `192.168.86.x`, ARP still egresses `wlan0`). See DECISION-031
for the full rationale and the MetalLB-vs-Cilium capability comparison.

Pool stays on the Wi-Fi subnet, so **the Tailscale subnet route `192.168.86.240/28` is unchanged**
(`homekube-main/ansible/roles/k8s-node/tasks/configure_tailscale_subnet.yml`). No Tailscale or
route-approval work in this spec.

## 3. Current state (verified 2026-06-20)

| Thing | Where | Current value |
|---|---|---|
| Cilium Helm values | `homekube-main/ansible/roles/cni/files/cilium-helm-values.yaml` | `devices: "eth0"`, `kubeProxyReplacement: true`, `routingMode: tunnel/vxlan`, `ipam: kubernetes`, no l2announcements |
| Cilium install/apply | `homekube-main` ansible `40-cni.yml` (`task 40-cni`, helm upgrade) | Cilium 1.19.4 |
| MetalLB Application | `homekube-apps/applications/wave-00-init/metallb.yaml` | chart 0.16.0, wave `-1`, `prune: true`, `frrk8s.enabled: false` |
| MetalLB CRs | `homekube-apps/applications/wave-00-init/metallb/` | `IPAddressPool 192.168.86.241-251`; `L2Advertisement` nodeSelector `control-plane DoesNotExist` (pi1/2/3) |
| Root kustomization | `homekube-apps/applications/kustomization.yaml` | line `- wave-00-init/metallb.yaml` |
| Tailscale route | `…/k8s-node/tasks/configure_tailscale_subnet.yml` | advertises `192.168.86.240/28` — **keep as-is** |

## 4. Target state

**Cilium Helm values** (`cilium-helm-values.yaml`) gain:
```yaml
devices: "eth0,wlan0,tailscale0"  # was "eth0"; tailscale0 added per DECISION-032 for Tailscale→VIP path

l2announcements:
  enabled: true
  # defaults: leaseDuration 15s / leaseRenewDeadline 5s / leaseRetryPeriod 2s.
  # Lower leaseDuration for faster failover at the cost of more API calls — leave default to start.

# Leader election for L2 announcements is API-chatty (one lease per announcing service).
# Raise the client-go rate limit so the agent does not get throttled. Tune up if logs show
# rate-limit warnings; these starting values are comfortable for a handful of LB services.
k8sClientRateLimit:
  qps: 50
  burst: 100
```
`kubeProxyReplacement: true` is already set and is a hard requirement for L2 announcements — do not change it. Leave `upgradeCompatibility`, `routingMode`, `ipam`, `hubble` untouched.

**New Cilium LB CRs**, GitOps-managed like the MetalLB CRs were. Create
`homekube-apps/applications/wave-00-init/cilium-lb/` with:

`pool.yaml`
```yaml
apiVersion: cilium.io/v2alpha1   # VERIFY served version at execution time — see §5 step 0
kind: CiliumLoadBalancerIPPool
metadata:
  name: homekube-pool
spec:
  blocks:
    - start: "192.168.86.241"
      stop: "192.168.86.251"
```

`l2policy.yaml`
```yaml
apiVersion: cilium.io/v2alpha1   # VERIFY served version at execution time — see §5 step 0
kind: CiliumL2AnnouncementPolicy
metadata:
  name: homekube-l2
spec:
  loadBalancerIPs: true
  nodeSelector:
    matchExpressions:
      - key: node-role.kubernetes.io/control-plane
        operator: DoesNotExist        # pi1/pi2/pi3 only — mirrors old L2Advertisement
  interfaces:
    - "^wlan0$"                        # announce on Wi-Fi only, not eth0/tailscale0
```

And an ArgoCD Application `homekube-apps/applications/wave-00-init/cilium-lb.yaml` that points
at `applications/wave-00-init/cilium-lb` (directory source, **no Helm chart** — Cilium itself is
installed by ansible, not ArgoCD), wave `-1`, `prune: true`, `selfHeal: true`. Model it on the
git-source half of `metallb.yaml`.

**Root kustomization**: remove `- wave-00-init/metallb.yaml`, add `- wave-00-init/cilium-lb.yaml`.

**Deletions**: `homekube-apps/applications/wave-00-init/metallb.yaml` and the `metallb/` directory.

## 5. Execution plan — ordered cutover

> ⚠️ **Correctness rule:** `wlan0` must NEVER be in Cilium `devices` while MetalLB VIPs still
> exist on the network — that is the exact DECISION-030 trap. Therefore **remove MetalLB fully
> before flipping Cilium to `eth0,wlan0`.** There is a short LB-IP outage window between MetalLB
> teardown and the Cilium policy going live; NodePort access is unaffected throughout.

Follow `feedback_ansible_execution` / `feedback_implementation_pace`: show each command and wait
for confirmation before running playbooks; one chunk at a time.

**Step 0 — Pre-flight (read-only).**
- `kubectl get crd | grep -i ciliumloadbalancer` and
  `kubectl get crd ciliumloadbalancerippools.cilium.io -o jsonpath='{.spec.versions[*].name}{"\n"}'`
  — confirm the served apiVersion (`v2alpha1` vs `v2`) and fix it in `pool.yaml` / `l2policy.yaml`
  before committing. Same for `ciciliuml2announcementpolicies` (check `kubectl api-resources | grep -i l2announce`).
- Capture current Cilium config: `kubectl -n kube-system get cm cilium-config -o yaml > /tmp/cilium-config.before.yaml`.
- Confirm a known LB service + its current MetalLB IP for later comparison (`kubectl get svc -A | grep LoadBalancer`).

**Step 1 — Remove MetalLB (GitOps).**
- Edit `homekube-apps/applications/kustomization.yaml`: drop the metallb line.
- `git rm` `metallb.yaml` and the `metallb/` dir. Commit + push (push needs explicit approval).
- ArgoCD prunes the `metallb` Application → `metallb-system` namespace, controller, speakers, and
  the `IPAddressPool`/`L2Advertisement` CRs are removed. Verify: `kubectl get ns metallb-system`
  returns NotFound (or terminating → gone), `kubectl get svc -A | grep LoadBalancer` shows the test
  service `EXTERNAL-IP` now `<pending>`. **From here LB IPs are down (expected); NodePort still up.**

**Step 2 — Flip Cilium to eth0,wlan0 + enable L2 (ansible).**
- Edit `cilium-helm-values.yaml` per §4. Update the inline comment on the `devices` line (it
  currently references DECISION-030's *reverted* attempt — now it's the chosen state, ref DECISION-031).
- Run `task 40-cni` (helm upgrade). Show the command first.
- `kubectl -n kube-system rollout restart ds/cilium` then `rollout status`.
- Verify: `cilium status` healthy; `cilium config view | grep -iE 'l2-announce|enable-l2'` shows
  enabled; `kubectl -n kube-system logs ds/cilium | grep -iE 'rate ?limit|FAILED'` is clean.
  Because MetalLB is gone, there are no foreign VIPs to probe — the DECISION-030 failure cannot recur.

**Step 3 — Apply Cilium LB CRs (GitOps).**
- Create `cilium-lb/pool.yaml`, `cilium-lb/l2policy.yaml`, `cilium-lb.yaml` (Application), add the
  Application to the root kustomization. Commit + push (approval).
- ArgoCD syncs. Cilium LB-IPAM assigns an IP from the pool to each LB service; the L2 policy makes
  pi1/2/3 announce it on `wlan0` via leader election.

**Step 4 — Validate (§6).**

**Step 5 — Finalize docs (§7).**

## 6. Validation / acceptance criteria

- [x] `kubectl get ciliumloadbalancerippool` shows `homekube-pool`, not disabled, no conflicts.
- [x] `kubectl get ciliuml2announcementpolicy` shows `homekube-l2`.
- [x] A test `type: LoadBalancer` service receives an IP from `192.168.86.241–251`
      (`kubectl get svc` EXTERNAL-IP populated). → `192.168.86.241` assigned instantly.
- [x] `kubectl get lease -n kube-system | grep -i l2announce` shows a lease held by one of pi1/2/3.
      → pi2 holding `cilium-l2announce-default-lb-test`.
- [~] From a host on home Wi-Fi: `arping` resolves the VIP to the leader node's MAC,
      and `curl http://<VIP>:<port>` returns the app (HTTP 200). → **Intermittent** — ARP works
      (pi2 responds correctly), but TCP sometimes fails mid-burst. See Backlog in `TODO.md`.
- [x] **From darth over Tailscale, away from home Wi-Fi** (the DECISION-030 regression check):
      36/36 successful curls over 3 minutes via `--interface utun8`. No `FAILED` neighbor entries.
      Required adding `tailscale0` to Cilium devices (DECISION-032).
- [x] Announcement only from pi1/pi2/pi3 (control-plane excluded) — leader is never pi0.
- [ ] Failover: cordon leader, confirm lease moves, uncordon. **Not yet tested — deferred to Backlog.**
- [x] `kubectl -n kube-system logs ds/cilium | grep -i 'rate ?limit'` clean under steady state.
- [x] NodePort access still works (no regression).

## 7. Documentation to update on completion — full MetalLB inventory

Every MetalLB mention in the project (all three repos), captured 2026-06-20. The cutover is not
done until the **Update** bucket is clear. **Re-run the sweep before declaring done:** from the
project root, `grep -rIl -i metallb . | grep -v /.git/` (and the same inside `homekube-main/` and
`homekube-apps/`, which are nested repos a top-level grep skips) should return only the Leave-bucket
files below.

**Update — these go stale the moment MetalLB is removed:**

| File | What to change |
|---|---|
| `CLAUDE.md` (top, line ~47) | Stack table: `\| Load Balancer \| MetalLB \|` → `\| Load Balancer \| Cilium LB-IPAM + L2 \|` |
| `README.md` (top, line ~46) | Component list `… · Grafana · Loki · MetalLB` → drop `MetalLB` (Cilium already leads the list; optionally note "Cilium (CNI + LB)") |
| `homekube-main/README.md` (lines ~95, ~119) | Mermaid node `app1[MetalLB]` and the apps-deployment list "(MetalLB, Longhorn, monitoring)" → Cilium LB |
| `homekube-main/ansible/roles/k8s-node/tasks/configure_tailscale_subnet.yml` (line ~7) | Task name comment "Advertise **MetalLB** pool via Tailscale subnet routing" → "Advertise **LoadBalancer** pool (Cilium LB-IPAM) …". The `192.168.86.240/28` route value is unchanged. |
| `.claude/commands/check-versions.md` (line ~27) | Remove the `helm repo add metallb …` line and any MetalLB chart-version check (Cilium is already version-tracked elsewhere). |
| `homekube-apps/CLAUDE.md` | Wave Structure table — replace `MetalLB` under `wave-00-init` with the Cilium LB CRs (`cilium-lb`). |
| `homekube-apps/README.md` | Deployed Components / "Adding an app": add a LoadBalancer = "Cilium LB-IPAM + L2 announcements" row (MetalLB was never added here — it never reached a working state). Per `feedback_readme_maintenance`. |
| `homekube-apps/applications/kustomization.yaml` | Remove `- wave-00-init/metallb.yaml`, add `- wave-00-init/cilium-lb.yaml` (this is execution Step 1/3, listed here for completeness). |
| `homekube-apps/applications/wave-00-init/metallb.yaml` + `metallb/` dir | **Delete** (execution Step 1). |

**Leave — historical record, do NOT edit:**

| File | Why keep |
|---|---|
| `DECISIONS.md` (019, 030, 031) | Decision log is append-only history; 031 supersedes but does not erase 019/030. |
| `CHANGELOG.md` | Append-only; past MetalLB entries are accurate for their date. Add the *new* completion entry (below), don't rewrite old ones. |
| `docs/specs/004-kubernetes-install.md` (line ~62) | Point-in-time spec describing Phase 5 as planned then; historical. |
| `docs/specs/005-…md` (capability 4) | Already annotated "superseded by spec 006"; retained as the MetalLB design record. |
| `docs/specs/006-…md` (this file) | The replacement spec itself. |

**Then, the live-status docs to finalize:**
- This spec — flip **Status** to `Done`, check the §6 boxes; append an Operational note if execution
  surfaced surprises (apiVersion was `v2`, rate limit needed raising, etc.).
- `DECISIONS.md` — add a one-line follow-up under DECISION-031 only if reality diverged from the plan.
- `CHANGELOG.md` — new dated entry: **Removed** MetalLB; **Added** Cilium LB-IPAM + L2 announcements
  (`cilium-lb` app) + the doc updates above; **Changed** `cilium-helm-values.yaml` (devices,
  l2announcements, rate limit); link DECISION-031 + this spec.
- `TODO.md` — tick the spec 006 Step 0–5 items.

## 8. Rollback

If validation fails and the cause isn't quickly fixable:
1. Revert the Cilium values commit (`devices: "eth0"`, drop l2announcements + rate limit) →
   `task 40-cni` → `rollout restart ds/cilium`.
2. Restore `metallb.yaml` + `metallb/` and the kustomization line; remove `cilium-lb*`. Push.
   ArgoCD redeploys MetalLB (back to the known not-reachable-but-stable state, NodePort working).

Keep step 1 (MetalLB removal), step 2 (Cilium flip), and step 3 (Cilium CRs) as **separate commits**
so any one can be reverted cleanly.

## 9. Notes / known gotchas

- **apiVersion drift:** Cilium has moved LB-IPAM/L2 CRDs from `v2alpha1` toward `v2` across releases.
  The §4 manifests say `v2alpha1` but **Step 0 must confirm** what 1.19.4 actually serves and correct
  the files before commit. Wrong apiVersion = silent no-op / sync error.
- **Rate-limit tuning:** `qps: 50 / burst: 100` is a starting point. If `kubectl -n kube-system logs
  ds/cilium` shows client-go throttling, raise both. More announcing services ⇒ more lease churn.
- **Source IP:** with `externalTrafficPolicy: Local`, Cilium eBPF preserves client source IP. Not
  required by this spec but worth setting on user-facing services (e.g. Grafana) later.
- **Why pool stays on Wi-Fi:** DECISION-019's reasoning (family devices reach LB IPs without router
  static routes) still holds and is preserved here — this change fixes *DNAT*, not the subnet choice.
