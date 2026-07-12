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

---

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

## 2026-06-29

### Changed
- Spec 005 cap-8 (Dashboards & Alerting) reviewed and rewritten: Grafana deployed as the `kube-prometheus-stack` subchart (re-enabled in `kube-prometheus.yaml`), exposed on Cilium LB-IPAM VIP `192.168.86.243`, stateless (no PVC); Loki added via `additionalDataSources`; Longhorn dashboard via sidecar ConfigMap; Telegram `bot_token_file` mount mechanism spelled out
- Removed stale MetalLB / NodePort `:30003` references from cap-8; Grafana TLS deferred from cap-8 to cap-9 (cap-9 §gains the IP-SAN cert constraint + acceptance box)

### Decisions
- [DECISION-036](DECISIONS.md) — Grafana as kube-prometheus-stack subchart; LB VIP `.243`; TLS deferred to cap-9

---

## 2026-06-22

### Added
- Cilium LB-IPAM + L2 announcements: `CiliumLoadBalancerIPPool` (`homekube-pool`, `192.168.86.241–251`) and `CiliumL2AnnouncementPolicy` (`homekube-l2`, wlan0, workers only) deployed via ArgoCD (`cilium-lb` app, wave -1)
- Network architecture diagram in `homekube-main/README.md` showing all three network planes (Tailscale, Wi-Fi, k8s switch) and both LB traffic paths

### Changed
- `cilium-helm-values.yaml`: `devices` → `eth0,wlan0,tailscale0`; added `l2announcements.enabled: true`; `k8sClientRateLimit qps:50/burst:100`
- `CLAUDE.md` stack table: MetalLB → Cilium LB-IPAM + L2
- `README.md`: stack line drops MetalLB, notes Cilium (CNI + LB)
- `homekube-main/README.md`: cluster architecture Mermaid updated (MetalLB → Cilium LB, pi1/2/pi3 corrected); network architecture diagram added
- `homekube-apps/CLAUDE.md` wave table: MetalLB → Cilium LB (pool + L2 policy)
- `homekube-apps/README.md` deployed components: added Cilium LB-IPAM, cert-manager, kubelet-csr-approver rows
- `configure_tailscale_subnet.yml` task name: "MetalLB pool" → "LoadBalancer pool (Cilium LB-IPAM)"
- `check-versions.md`: removed metallb helm repo line

### Removed
- MetalLB: `metallb.yaml` Application, `metallb/` CRs, `metallb-system` namespace; 9 MetalLB CRDs manually deleted post-ArgoCD-prune (Helm safety policy prevents auto-deletion)

### Decisions
- [DECISION-032](DECISIONS.md) — add `tailscale0` to Cilium devices so `cil_from_netdev` intercepts Tailscale → VIP traffic on pi0; validated 36/36 over 3 min. Wi-Fi path intermittent (wlan0 dual-use + BPF reload windows); tracked in Backlog.

---

## 2026-06-20

### Added
- `docs/specs/006-cilium-native-loadbalancer.md` — executable spec to replace MetalLB with Cilium-native LB-IPAM + L2 announcements; written self-contained for execution in a later session. No cluster changes yet — planning only.

### Changed
- `docs/specs/005-production-cluster-setup.md` — capability 4 marked **superseded by spec 006**; its acceptance boxes flagged as not actually met (LB IPs unreachable per DECISION-030).
- `TODO.md` — capability 4 metallb item replaced with the spec 006 cutover step list (Steps 0–5).

### Decisions
- [DECISION-031](DECISIONS.md) — replace MetalLB with Cilium-native LB-IPAM + L2 announcements; resolves the DECISION-030 dead end while keeping eBPF kube-proxy replacement and home-Wi-Fi reachability. Pool and Tailscale `192.168.86.240/28` route unchanged.

---

## 2026-06-18

### Added
- kubelet-csr-approver `1.2.14` deployed to `kube-system` (spec 005 capability 3); `bypassDnsResolution: true` required because node hostnames are not resolvable from within the cluster
- Ansible: `configure_kubelet_node_ip.yml` task sets `--node-ip={{ node_switch_ip }}` on all nodes via `/etc/default/kubelet`, preventing Wi-Fi and Tailscale IPs from appearing in kubelet serving CSR SANs

### Operational
- cert-manager validation: applied a test `Certificate` against `ClusterIssuer/homekube-ca`, confirmed `Ready=True` and secret populated, cleaned up — spec 005 capability 2 acceptance complete
- kubelet-csr-approver: accidentally deleted `kubelet-client-current.pem` target on pi2 during serving cert teardown; recovered via `kubeadm token create` bootstrap re-join

---

## 2026-05-23 — Baseline

End of Phase 5 bootstrap. Cluster is a working, minimalistic Kubernetes installation. Future changes are tracked from this point onward.

### Cluster state at baseline
- 4-node `kubeadm` cluster, Kubernetes **1.36.1** (control plane: `pi0`; workers: `pi1`, `pi2`, `pi3`)
- CNI: **Cilium 1.19.4**
- GitOps: **ArgoCD 9.5.14**, root-app synced (App-of-Apps)
- **metrics-server** installed; `kubectl top nodes` returns CPU/memory for all nodes
- `argocd-config` synced (NodePort `:30000`)
- ArgoCD waves wired: `wave-00-init` active; `wave-01-apps`, `wave-02-custom` placeholders

### Not yet present (Phase 5 targets — see `docs/specs/005-production-cluster-setup.md`)
- Persistent storage (Longhorn)
- Service exposure (MetalLB)
- Observability (Prometheus / Loki / Grafana)
- Identity / SSO (Dex)
- Service mesh (Istio)
- Backups & DR (Velero + etcd snapshots + Longhorn → S3)

### Known operational gaps
- kubelet `kubernetes.io/kubelet-serving` CSRs require manual bulk approval
- No off-cluster backups
- All cluster UIs exposed via NodePort; no DNS, no ingress

### Decisions captured during phases 1–5
See `DECISIONS.md` (entries 001–016).
