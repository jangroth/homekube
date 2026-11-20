# Coder runs agent workspaces

Self-hosted Coder supplies the workspace lifecycle (create, stop, delete, agent, SSH), so there is no custom controller. It has its own Postgres, logs in through Dex with signups off and keeps a `+breakglass` password owner for when OIDC breaks. Workspaces run without root, and the template is pushed by hand from `homekube-apps/manual/coder-templates/` on `main`.

Replaces [Decision 081](../archive/decisions/DECISIONS.md).
