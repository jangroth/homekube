# Terraform owns AWS-account infrastructure and Infisical configuration

Resources in an AWS account live under `homekube-main/terraform/<resource>/`, with local gitignored state, applied by hand from a human AWS identity: changes are rare and high blast radius. Infisical's configuration (projects, folders, machine identities, their Kubernetes Auth and permissions) lives under `homekube-main/terraform/infisical/` the same way, applied with an Infisical admin identity kept in the password manager; secret values are entered by hand and never pass through Terraform state. Ansible owns the Pi fleet and ArgoCD owns in-cluster resources; Terraform configures accounts, never Kubernetes resources.

Replaces [Decision 058](../archive/decisions/DECISIONS-2026-Q3.md).
