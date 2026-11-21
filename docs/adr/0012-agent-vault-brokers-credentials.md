# Agent Vault brokers agents' API credentials; the Infisical operator syncs secrets

Agents reach external APIs through Infisical Agent Vault, an HTTPS proxy in namespace `agent-vault` that injects credentials, so the agent never holds them. The exception is a protocol the proxy can't carry: Hermes's Coder token (`coder ssh` uses WebSockets, and coderd is in-cluster) is held by Hermes itself, kept narrow by API-token scopes and a non-Owner user ([#105](https://github.com/jangroth/homekube/issues/105)). Secret sync into the cluster uses the Infisical operator with Kubernetes Auth, not External Secrets Operator.

Replaces [Decision 080](../archive/decisions/DECISIONS.md).
