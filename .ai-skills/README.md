# AI Support Architecture for homekube

**Created:** 31 January 2026
**Target:** GitHub Copilot in VS Code
**Repo:** [jangroth/homekube](https://github.com/jangroth/homekube)

---

## Summary

This repository has been architected for optimal AI interpretability using a multi-layered context system:

### 1. **Primary AI Instructions** (`.github/copilot-instructions.md`)
- **Purpose:** Main file read by GitHub Copilot automatically
- **Contains:** Architectural constraints, component versions, workflows, coding standards
- **Audience:** AI assistant (prescriptive rules, "never do X")
- **Location:** `homekube-main/.github/copilot-instructions.md`

### 2. **Infrastructure Source of Truth** (`AI-CONTEXT.md`)
- **Purpose:** Comprehensive reference for cluster architecture and operational facts
- **Contains:** Network topology, component matrix, runbooks, decision trees
- **Audience:** AI + human reference (canonical infrastructure knowledge)
- **Location:** `homekube-main/AI-CONTEXT.md`

### 3. **Skill Definitions** (`.ai-skills/`)
- **Purpose:** Detailed coding patterns and anti-patterns by technology
- **Contains:**
  - `shell-scripting.md` — Idempotency, error handling, cluster awareness
  - `ansible.md` — Variable hierarchy, module choice, handlers, testing
  - `kubernetes-manifests.md` — Resource limits, storage, labels, security
- **Audience:** AI reference (examples-driven, "do this not that")
- **Location:** `homekube-main/.ai-skills/`

### 4. **VS Code Configuration** (`.vscode/settings.json`)
- **Purpose:** Optimise editor for Copilot, YAML schemas, file associations
- **Contains:** Ansible linting, Kubernetes schema validation, Taskfile integration
- **Audience:** VS Code (enhances AI context via language services)
- **Location:** Workspace root `.vscode/settings.json`

---

## File Placement Strategy

```
homekube/  (workspace root)
├── .vscode/
│   └── settings.json              # VS Code + Copilot config
│
├── homekube-main/                 # Main infrastructure repo
│   ├── .github/
│   │   └── copilot-instructions.md  # PRIMARY: Copilot reads this automatically
│   │
│   ├── .ai-skills/                # SKILLS: Detailed patterns by tech
│   │   ├── ansible.md
│   │   ├── shell-scripting.md
│   │   └── kubernetes-manifests.md
│   │
│   ├── AI-CONTEXT.md              # REFERENCE: Infrastructure source of truth
│   │
│   ├── ansible/                   # Ansible playbooks and roles
│   ├── doc/                       # Human documentation
│   ├── scripts/                   # Shell scripts
│   └── Taskfile.yml               # Task automation
│
├── homekube-apps/                 # ArgoCD application manifests
├── argocd-example-apps/           # Upstream examples
└── cks/                           # Kubernetes certification notes
```

---

## How It Works

### For GitHub Copilot (Chat & Inline Suggestions)

1. **Automatic Context:** Copilot reads `.github/copilot-instructions.md` when workspace is opened
2. **On-Demand Context:** User can reference `AI-CONTEXT.md` or `.ai-skills/*.md` in chat prompts
3. **Schema Awareness:** VS Code YAML schemas (in `settings.json`) provide Kubernetes/Ansible autocomplete
4. **File Associations:** Ansible files correctly identified, enabling Ansible-specific AI suggestions

### For User (Developer Experience)

1. **Single Source of Truth:** Component versions in `ansible/group_vars/all.yml` → reflected in `AI-CONTEXT.md`
2. **Context Refresh:** When versions change, regenerate `AI-CONTEXT.md` (see section 15)
3. **Discoverability:** README or contributing guide points to `.github/copilot-instructions.md`
4. **Progressive Disclosure:**
   - Quick ref: `.github/copilot-instructions.md` (high-level rules)
   - Deep dive: `.ai-skills/*.md` (detailed patterns)
   - Ops ref: `AI-CONTEXT.md` (infrastructure facts)

---

## Maintenance Workflow

### When to Update AI Context Files

| Trigger | Files to Update | How |
|---------|-----------------|-----|
| Component version change | `AI-CONTEXT.md` (section 6) | Update version matrix after changing `group_vars/all.yml` |
| New node added/removed | `AI-CONTEXT.md` (section 1) | Update hardware topology table |
| CNI/CSI change | `.github/copilot-instructions.md` + `AI-CONTEXT.md` | Major architectural change, rewrite relevant sections |
| New skill/pattern | `.ai-skills/<tech>.md` | Add new example or update anti-pattern |
| Playbook workflow changes | `.github/copilot-instructions.md` (Ansible section) | Update execution order or idempotency notes |

### Regeneration Script (Future)
```bash
#!/bin/bash
# scripts/regenerate-ai-context.sh
set -euo pipefail

echo "Regenerating AI-CONTEXT.md from live cluster state..."

# Extract versions from group_vars
KUBE_VERSION=$(grep "kubernetes_version:" ansible/group_vars/all.yml | awk '{print $2}' | tr -d '"')
CILIUM_VERSION=$(grep "cilium_version:" ansible/group_vars/all.yml | awk '{print $2}' | tr -d '"')
# ... etc

# Query cluster state
kubectl get nodes -o wide > /tmp/nodes.txt
kubectl get sc > /tmp/storage.txt

# Update AI-CONTEXT.md (templated sections)
# ... implementation needed

echo "✓ AI-CONTEXT.md updated"
```

---

## AI Assistant Decision Framework

### Query Routing (Where to Look First)

**Q: "What's the Kubernetes version?"**
→ Check: `AI-CONTEXT.md` section 6 (Component Version Matrix)

**Q: "How do I write an idempotent Ansible task?"**
→ Check: `.ai-skills/ansible.md` section 2 (Idempotency)

**Q: "Can I use Calico instead of Cilium?"**
→ Check: `.github/copilot-instructions.md` section "Do Not Suggest"

**Q: "How do I add a new ArgoCD app?"**
→ Check: `.github/copilot-instructions.md` section "Operational Workflows"

**Q: "What storage class should I use?"**
→ Check: `AI-CONTEXT.md` section 3 (Storage Architecture)

**Q: "Should this script use `set -e`?"**
→ Check: `.ai-skills/shell-scripting.md` section 2 (Error Handling)

---

## Limitations and Trade-offs

### What This Architecture Achieves
✅ AI understands critical "never do this" constraints (network CIDRs, CNI choice)
✅ AI suggests idiomatic code patterns (Ansible modules over shell commands)
✅ AI knows cluster topology without querying (static IPs, node roles)
✅ AI generates manifests with correct storage classes and resource limits
✅ Reduces hallucinations (versions, component compatibility)

### What It Doesn't Replace
❌ **Live Cluster State:** AI can't know which pods are running (must query via `kubectl`)
❌ **Secret Values:** AI should never generate actual passwords/tokens
❌ **Dynamic Decisions:** AI can't predict network performance or choose optimal resource limits
❌ **Human Judgement:** Architectural changes (e.g., replacing Longhorn) require human approval

---

## Recommended VS Code Extensions

To maximise AI effectiveness, install these extensions:

```json
{
  "recommendations": [
    "github.copilot",              // GitHub Copilot
    "github.copilot-chat",         // Copilot Chat
    "redhat.vscode-yaml",          // YAML language server (schema validation)
    "redhat.ansible",              // Ansible language server
    "ms-kubernetes-tools.vscode-kubernetes-tools",  // Kubernetes tools
    "tim-koehler.helm-intellisense",  // Helm chart autocomplete
    "timonwong.shellcheck",        // Shell script linting
    "foxundermoon.shell-format"    // Shell script formatting
  ]
}
```

Save as `homekube/.vscode/extensions.json`.

---

## Future Enhancements

### Potential Additions
1. **`.copilot-context.yaml`** — Structured metadata for Copilot (if supported in future)
2. **Pre-commit Hooks** — Validate manifests against schemas before commit
3. **AI Context Validation** — Script to check `AI-CONTEXT.md` matches `group_vars/all.yml`
4. **Skill Tests** — Shell scripts to test idempotency patterns from `.ai-skills/`
5. **Copilot Workspace Prompts** — Saved prompts for common tasks (e.g., "add new ArgoCD app")

### Alternative Tools (Beyond GitHub Copilot)
This architecture is designed for GitHub Copilot, but can be adapted:
- **Cursor:** Rename `.github/copilot-instructions.md` → `.cursorrules`
- **Claude Desktop:** Use `AI-CONTEXT.md` as project context file
- **Windsurf:** Use `.windsurfrules` (similar structure to `.cursorrules`)
- **Cody:** Use `.cody/context.md` (similar to `AI-CONTEXT.md`)

---

## Testing the AI Setup

### Verification Checklist

1. **Open Workspace in VS Code**
2. **Trigger Copilot Chat** (Cmd+I or chat panel)
3. **Ask Test Questions:**
   - "What CNI is this cluster using?" → Should answer "Cilium 1.18.2"
   - "What storage class should I use for a new PVC?" → Should answer "longhorn"
   - "Can I use Docker commands on the nodes?" → Should say "No, use containerd/crictl"
   - "Write an Ansible task to install a package" → Should use `ansible.builtin.apt`, not `shell`
4. **Check Inline Suggestions:**
   - Open `ansible/roles/<role>/tasks/main.yml`
   - Start typing a task → Copilot should suggest Ansible module syntax
   - Open `homekube-apps/applications/wave-01-apps/<app>.yaml`
   - Start typing a manifest → Copilot should suggest Kubernetes resources with labels

---

## Appendix: File Cross-References

| Topic | Primary Source | Supporting Sources |
|-------|----------------|--------------------|
| Kubernetes Version | `AI-CONTEXT.md` §6 | `ansible/group_vars/all.yml`, `README.md` |
| Network CIDRs | `AI-CONTEXT.md` §2 | `.github/copilot-instructions.md` §3 |
| Storage Classes | `AI-CONTEXT.md` §3 | `.ai-skills/kubernetes-manifests.md` §3 |
| Ansible Idempotency | `.ai-skills/ansible.md` §2 | `.github/copilot-instructions.md` §7 |
| Shell Error Handling | `.ai-skills/shell-scripting.md` §2 | `.github/copilot-instructions.md` §7 |
| ArgoCD App Structure | `AI-CONTEXT.md` §5 | `.ai-skills/kubernetes-manifests.md` §10 |
| Node Topology | `AI-CONTEXT.md` §1 | `README.md`, `ansible/inventory/hosts` |
| Playbook Execution Order | `.github/copilot-instructions.md` §4 | `AI-CONTEXT.md` §7, `ansible/README.md` |

---

**End of AI Support Architecture Documentation**

For questions or improvements, update this file and relevant skill documents.
