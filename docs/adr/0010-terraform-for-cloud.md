# Terraform owns AWS-account infrastructure

Resources in an AWS account live under `homekube-main/terraform/<resource>/`, with local gitignored state, applied by hand from a human AWS identity: changes are rare and high blast radius. Ansible owns the Pi fleet and ArgoCD owns in-cluster resources; Terraform stops at the cloud boundary.

Replaces [Decision 058](../archive/decisions/DECISIONS-2026-Q3.md).
