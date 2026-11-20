# Renovate owns versions; components track the latest GA

Every component tracks its latest upstream GA release, never a pre-release, so the learning cluster carries no version debt. Versions live in `homekube-main/ansible/group_vars/all.yml` and the `targetRevision` fields in `homekube-apps`, and Renovate proposes every bump. A held version is an explicit Renovate rule plus an ADR (see ADR-0004).

Replaces [Decisions 017](../archive/decisions/DECISIONS-2026-Q2.md) and [064](../archive/decisions/DECISIONS-2026-Q3.md).
