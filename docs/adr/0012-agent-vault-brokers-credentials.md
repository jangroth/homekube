# Agent Vault brokers agents' API credentials; the Infisical operator syncs secrets

Agents reach external APIs through Infisical Agent Vault, an HTTPS proxy in namespace `agent-vault` that injects credentials, so the agent never holds them. The exception is Hermes's control-plane credentials, which the proxy can't carry, held by Hermes itself: its Coder token (`coder ssh` uses WebSockets, and coderd is in-cluster), kept narrow by API-token scopes and a non-Owner user ([#105](https://github.com/jangroth/homekube/issues/105)); and its Agent Vault machine identity, which mints the sessions the proxy grants, kept narrow by the Member role and grants on per-repo bundles only ([#107](https://github.com/jangroth/homekube/issues/107)). Secret sync into the cluster uses the Infisical operator with Kubernetes Auth, not External Secrets Operator.

Replaces [Decision 080](../archive/decisions/DECISIONS.md).
