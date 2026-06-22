---
description: Check pinned component versions against latest upstream releases
allowed-tools: Bash, Read, WebSearch
---

Check all pinned component versions in homekube against the latest upstream releases and report what's outdated.

## Step 1 — Collect current versions

Read the two sources of truth:

**Ansible-managed (non-ArgoCD):** `homekube-main/ansible/group_vars/all.yml`
Extract these variables: `argocd_helm_chart_version`, `cilium_version`, `containerd_version`, `etcdctl_version`, `kubernetes_version`, `longhorn_version`.

**ArgoCD-managed (Helm charts):** scan all `*.yaml` files under `homekube-apps/applications/` and extract rows where `chart:` and `targetRevision:` are present (skip `repoURL: https://github.com/` — those are git sources, not Helm charts).

Build a combined list: component name, Helm repo URL (if applicable), chart name, current version.

## Step 2 — Look up latest versions

**Helm charts** — add repos and query:

```sh
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add cilium https://helm.cilium.io
helm repo add longhorn https://charts.longhorn.io
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

For each Helm chart, run:
```sh
helm search repo <repo>/<chart> --output json | jq -r '.[0].version'
```

**Non-Helm components** — use WebSearch to find the latest stable GitHub release:
- Kubernetes: search "kubernetes latest stable release site:kubernetes.io/releases"
- Cilium: search "cilium latest stable release site:github.com/cilium/cilium/releases"
- containerd: search "containerd latest release site:github.com/containerd/containerd/releases"
- etcdctl: search "etcd latest release site:github.com/etcd-io/etcd/releases"

## Step 3 — Report

Output a markdown table sorted by status (outdated first):

| Component | Source | Current | Latest | Status |
|-----------|--------|---------|--------|--------|
| argocd | Ansible | 9.5.14 | ... | ✅ / ⚠️ |
| ... | | | | |

Strip leading `v` prefixes before comparing versions. Mark as ⚠️ **outdated** if latest > current (semver). Mark as ✅ **current** if they match. Mark as ❓ **unknown** if the latest version could not be determined.

End with:
- Count of outdated, current, and unknown
- For each outdated component, a one-line note on where to bump it (which file and variable/field)
