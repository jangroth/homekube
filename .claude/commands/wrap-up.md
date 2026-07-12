---
description: Update GitHub Issues and DECISIONS.md at the end of a session
allowed-tools: Read, Edit, Write, Bash
---

Review this session and update the project tracking files.

1. Read `DECISIONS.md` in the workspace root. Open tasks are tracked as GitHub Issues on `jangroth/homekube` (single tracker for all three repos), not a file — use `gh issue list --repo jangroth/homekube` to check current state.

2. Reconcile GitHub Issues on `jangroth/homekube`:
   - Close any issues resolved this session (`gh issue close <n> --repo jangroth/homekube --comment "..."`)
   - Open issues for any new tasks that came up, labelled `area:*`, one of `criticality:blocker`/`degraded`/`polish`, `repo:*` (which repo the fix lands in — `homekube`/`homekube-main`/`homekube-apps`), and `agent-safe` if it meets the criteria (no open design decision, no destructive/irreversible live action, no physical/external-account step, lands as a PR)
   - Skip this step if nothing changed

3. Update `DECISIONS.md`:
   - Add an entry for any significant decision made this session at the **top** of the file (newest first)
   - Only log decisions where the rationale would not be obvious from reading the code — skip implementation details
   - Use the next available number and today's date

4. Summarise what was done this session in 3-5 bullet points.

5. If `DECISIONS.md` changed, remind the user to commit the workspace repo. Issue changes are already live on GitHub — no commit needed for those.
