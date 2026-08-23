# harness

Enforcement layer for AI-assisted development. Hooks, gates, and evals that
make the workflow (SDD, strict TDD, subagent-only edits, review gate,
live-test-before-PR) mandatory instead of advisory.

## Install

```
claude plugin marketplace add juandarn/harness
claude plugin install harness@harness
```

Then, **required per machine**:

`/plugin` → Marketplaces → harness → Enable auto-update

Version resolves to the git commit SHA (no declared `version` field), so
auto-update is how you get changes.

## Status

Fase 2 of 6:

1. Skeleton
2. **Hooks** ← you are here
3. Skills
4. Knowledge layer
5. Evals
6. Dogfooding

Implemented: PreToolUse delegation gate, PostToolUse comment nag, and the
Stop hook checklist (opt-in via `harness.gates.json`). Skills and evals are
not implemented yet.

## Docs

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions.
