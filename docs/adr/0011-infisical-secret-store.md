# Infisical is the secret store; sealed-secrets covers only bootstrap

Self-hosted Infisical holds cluster and operator secrets. sealed-secrets stays for what must exist before Infisical: Infisical's own keys and database credentials, and the operator's credentials. The sealed-secrets controller runs with `keyrenewperiod: "0"`: renewal never re-sealed old secrets or limited a cluster compromise, and each new key needed a manual export to survive a rebuild. Rotation is manual and is followed by a fresh key export.

Replaces [Decisions 020](../archive/decisions/DECISIONS-2026-Q2.md), [076 and 079](../archive/decisions/DECISIONS.md).
