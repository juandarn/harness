---
name: review-gate
description: "Trigger: \"review gate\", finishing implementation, or right before opening a PR. Launches fresh-context transversal review via subagents and writes .harness/review-report.md evidence."
---

## Why

The orchestrator session that implemented the change has seen its own
reasoning too many times to review it objectively. Review runs in fresh
context, on the diff only, not the whole repo.

## Procedure

1. **Determine diff scope** — the range of commits/files for this change,
   not the entire repository.
2. **Launch reviewers via the Task tool**, using the locally available
   reviewer agents:
   - `security-checker` — always, regardless of stack.
   - `backend-reviewer` — when the diff touches backend code.
   - `frontend-reviewer` — when the diff touches frontend code.
   - `data-reviewer` — when the diff touches dbt/warehouse/data code.
3. Give each reviewer the **diff scope**, not repo-wide access — they review
   what changed, not what already existed.
4. **Resolve findings**: every finding is either fixed or explicitly waived
   by the user. Do not silently drop findings; do not auto-waive them
   yourself.

## Evidence

Write `.harness/review-report.md` with:

- Date
- Diff range reviewed
- Reviewers run
- Findings, and their resolution (fixed / waived — by whom)

This file is what the Stop gate checks when the repo declares
`review-evidence` in `harness.gates.json`. **Never write it without
actually running the review** — the gate exists to prove review happened,
not to be satisfied by a placeholder file.
