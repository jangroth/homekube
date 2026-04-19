# Decision Log

---

## 001 — Workspace structure (2026-04-19)

**Decision:** Use a thin parent git repo at `/Users/jan/Projects/kube/homekube/` to track shared AI context, todo, and decisions. Child repos (`homekube-main`, `homekube-apps`) remain independent git repos — not submodules.

**Rationale:** Keeps shared documentation versioned without submodule complexity. Parent `CLAUDE.md` is automatically loaded by Claude Code when working in any child directory. Three separate GitHub repos.

**Repos:** `jangroth/homekube` (workspace), `jangroth/homekube-main`, `jangroth/homekube-apps`

---

## 002 — Spec-driven AI development (2026-04-19)

**Decision:** Follow spec-driven development for all significant work. Before implementation, write a spec in `docs/specs/NNN-title.md` defining: problem, acceptance criteria, out-of-scope, and approach.

**Rationale:** Keeps the human in the driver's seat on *what* gets built. Specs are learning artifacts. Prevents AI from going off in unexpected directions. Aligns with the goal of learning AI-driven development.

---

## 003 — Nuke and reprovision (2026-04-19)

**Decision:** Reprovision all 4 pis from scratch (fresh SD card flash) rather than attempting to diagnose and repair the existing cluster state.

**Rationale:** Cluster state is unknown after months dormant. Suspected OOM crash. Clean start is more reliable and gives a known baseline. The reprovisioning process is well-documented in ansible.

---

## 004 — NVMe boot requires human checkpoint (2026-04-19)

**Decision:** The one-time physical NVMe hardware setup step per pi is a documented human checkpoint. Claude will not attempt to automate or skip this step.

**Rationale:** Vendor instructions require physical interaction with the NVMe hardware. This cannot be done over SSH. Ansible handles everything before and after this step.

---

## 005 — Trust and autonomy policy (2026-04-19)

**Decision:** Start with "Claude proposes, human approves" for all destructive or irreversible operations. Build autonomy incrementally as trust is established.

**Rationale:** New collaboration — need to understand what Claude does before granting autonomous execution of ansible playbooks, node reboots, etc.
