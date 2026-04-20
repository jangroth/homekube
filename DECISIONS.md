# Decision Log

---

## 004 — ansible-core over full ansible bundle (2026-04-20)

**Decision:** Use `ansible-core` (not the full `ansible` package) with explicit collection management via `ansible/requirements.yml`.

**Rationale:** Leaner install, forces explicit declaration of what collections are actually used, easier to pin precisely. Collections required: `ansible.posix`, `community.crypto`, `community.general`, `kubernetes.core`.

---

## 003 — Nuke and reprovision (2026-04-19)

**Decision:** Reprovision all 4 pis from scratch (fresh SD card flash) rather than attempting to diagnose and repair the existing cluster state.

**Rationale:** Cluster state is unknown after months dormant. Suspected OOM crash. Clean start is more reliable and gives a known baseline.

---

## 002 — Spec-driven AI development (2026-04-19)

**Decision:** Follow spec-driven development for all significant work. Before implementation, write a spec in `docs/specs/NNN-title.md` defining: problem, acceptance criteria, out-of-scope, and approach.

**Rationale:** Keeps the human in the driver's seat on *what* gets built. Specs are learning artifacts. Prevents AI from going off in unexpected directions. Aligns with the goal of learning AI-driven development.

---

## 001 — Workspace structure (2026-04-19)

**Decision:** Use a thin parent git repo at `/Users/jan/Projects/kube/homekube/` to track shared AI context, todo, and decisions. Child repos (`homekube-main`, `homekube-apps`) remain independent git repos — not submodules.

**Rationale:** Keeps shared documentation versioned without submodule complexity. Parent `CLAUDE.md` is automatically loaded by Claude Code when working in any child directory. Three separate GitHub repos.

**Repos:** `jangroth/homekube` (workspace), `jangroth/homekube-main`, `jangroth/homekube-apps`
