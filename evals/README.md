# Evals

`claude plugin eval` suites that verify workflow compliance, not code quality.

Checked:
- Orchestrator never edits code inline (delegates to subagents).
- Strict TDD is followed (test before implementation).
- The review gate runs before a PR is opened.
- No comment block exceeds 3 consecutive lines.

Not checked: correctness, style, or performance of the code itself — that is
`code-review`'s job, not this plugin's.

Empty for now. Populated in Fase 5 (see `docs/ARCHITECTURE.md`).
