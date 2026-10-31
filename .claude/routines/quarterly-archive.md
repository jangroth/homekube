# Quarterly archive routine

Run quarterly by the "homekube - quarterly changelog/decisions archive" Claude Code routine. The routine prompt only points to this file.

## Routine settings

| Setting       | Value                                                                 |
|---------------|-----------------------------------------------------------------------|
| Trigger       | `trig_01PyasKTeDUn91Vfumf91FYr`                                       |
| Schedule      | `0 14 1 1,4,7,10 *`: 14:00 UTC on 1 Jan/Apr/Jul/Oct (00:00 AEST on the 2nd) |
| Model         | claude-sonnet-5                                                       |
| Allowed tools | Bash, Read, Write, Edit, Glob, Grep, WebFetch, WebSearch              |
| Environment   | `claude-code-homekube`, see [cloud-environment.md](cloud-environment.md) |
| Source        | `jangroth/homekube`                                                   |
| Connectors    | Claude_Code_Remote only                                               |

## Prompt

GraphQL is blocked in cloud sessions, so `gh pr create` / `gh pr edit` fail; use `gh api` (REST).

1. Dry-run `python3 scripts/archive_quarter.py` and keep its output.
2. If it reports nothing to archive for both `CHANGELOG.md` and `DECISIONS.md`, exit cleanly with that summary. Do not create a branch or PR.
3. Otherwise run `python3 scripts/archive_quarter.py --apply`.
4. Check `git status` and `git diff`: only `CHANGELOG.md`, `DECISIONS.md` and the new `CHANGELOG-<YYYY>-Q<N>.md` / `DECISIONS-<YYYY>-Q<N>.md` may have changed. If anything else changed, stop and report it.
5. Create a new branch named `auto/archive-quarter-<YYYY>-Q<N>` from `origin/main`, where Q<N> is the quarter just archived per the script's output.
6. Commit with a message naming the archived quarter and the entry counts from the script's output, and push the branch.
7. Open a PR against `main`: `gh api repos/jangroth/homekube/pulls -f title="Archive <YYYY> Q<N> into CHANGELOG-<YYYY>-Q<N>.md / DECISIONS-<YYYY>-Q<N>.md" -f head=<branch> -f base=main -f body=<body>`. Put the dry-run output (entry counts, date ranges) in the body.
8. Assign the PR to jangroth: `gh api repos/jangroth/homekube/issues/<pr-number>/assignees -f "assignees[]=jangroth"`. It is for human review. Do not auto-merge.
9. Do not modify this file or `cloud-environment.md` unless explicitly asked.
