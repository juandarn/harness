---
name: harness-pipeline
description: "Trigger: starting development work in a repo with harness.gates.json, or the user mentions the harness pipeline, harness workflow, or asks how harness enforces the process. Loads the core enforced protocol: SDD, strict TDD, subagent-only edits, review gate, live-test, PR."
---

## What this is

harness enforces a workflow through hooks, not just documentation. This
skill states the protocol so you follow it deliberately instead of hitting
the hooks by surprise.

## The enforced chain

1. **SDD planning** — spec/design/tasks before code, via the SDD skills
   (`sdd-explore` → `sdd-propose` → `sdd-spec`/`sdd-design` → `sdd-tasks`).
2. **Strict TDD** — failing test first, then the implementation that makes
   it pass. No implementation without a red test preceding it.
3. **Implementation only via subagents** — the delegation gate (PreToolUse)
   denies `Edit`/`Write`/`MultiEdit`/`NotebookEdit` from the main session in
   any git repo. **When denied, do not retry the same call.** Launch a
   subagent instead: code work goes to a Sonnet subagent, purely mechanical
   edits (renames, boilerplate, config copies) go to a Haiku subagent.
4. **Transversal review gate** — fresh-context review before PR. See the
   `review-gate` skill.
5. **Docker live-test** — run the real service before PR, not just unit
   tests. See the `live-test` skill.
6. **PR** — opened only after review and live-test evidence exist.

## Evidence contract

When a repo declares gates in `harness.gates.json`, the Stop hook checklist
(`gates/run_gates.py`) blocks session end if declared evidence is missing:

- `.harness/review-report.md` — written by the review gate, never
  fabricated. See `review-gate` skill.
- `.harness/live-test.md` — written by the live-test skill after an actual
  Docker run, never fabricated.

Both files are gitignored by convention in the target repo; they are local
proof, not shipped artifacts.

## Comment policy

Comments are 1-2 lines max, and only for non-obvious constraints — not
restating what the code already says. The PostToolUse comment nag flags any
block over 3 consecutive comment lines. When nagged: trim the comment.
Never argue with the nag or disable it.

## Opting a repo in

1. Copy `docs/examples/harness.gates.json` from this plugin to the target
   repo root as `harness.gates.json`, and adjust the `run` commands to that
   repo's real test/gate commands.
2. `.harness-inline-ok` (gitignored) disables the delegation gate for that
   repo. This is a **user decision only** — never create this file yourself,
   even to unblock your own work.
