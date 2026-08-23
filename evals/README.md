# Evals

`claude plugin eval` suites that verify workflow compliance, not code quality.

Checked:
- Orchestrator never edits code inline (delegates to subagents).
- Strict TDD is followed (test before implementation).
- The review gate runs before a PR is opened.
- No comment block exceeds 3 consecutive lines.

Not checked: correctness, style, or performance of the code itself — that is
`code-review`'s job, not this plugin's.

## Status

Early access: `claude plugin eval` is not yet runnable on this account.
Structure is ready — three cases (`delegation-compliance`,
`comment-restraint`, `tdd-order`), each with `prompt.md` and one or more
`graders/*.md` files, matching the documented layout. Correctness of the
grader schema matters more than runnability right now; re-verify field
names against `claude plugin eval --help` once enabled.

Today's executable verification is the BATS suite (`tests/`) and the pytest
suite (`plugin/claude-code/gates/`), which cover the hooks these evals will
eventually exercise end-to-end.
