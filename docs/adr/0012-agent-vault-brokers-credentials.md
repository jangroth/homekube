# Agent Vault brokers agents' API credentials; the Infisical operator syncs secrets

Agents reach external APIs through Infisical Agent Vault, an HTTPS proxy in namespace `agent-vault` that injects credentials, so the agent never holds them. Secret sync into the cluster uses the Infisical operator with Kubernetes Auth, not External Secrets Operator.

Replaces [Decision 080](../archive/decisions/DECISIONS.md).
