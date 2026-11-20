# cert-manager deploys as two ArgoCD Applications

`cert-manager` (wave -1, the chart) and `cert-manager-config` (wave 0, the ClusterIssuers) stay separate: the API server validates cert-manager resources through its admission webhook, and one Application can apply the issuers before the webhook is ready.

Replaces [Decision 027](../archive/decisions/DECISIONS-2026-Q2.md).
