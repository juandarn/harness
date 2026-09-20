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

Fase 4 of 6:

1. Skeleton
2. Hooks
3. Skills
4. **Evals** ← you are here
5. Knowledge layer
6. Dogfooding

Implemented: blocking, fail-closed hooks (commit/push gate, TDD order gate,
SDD artifact gate, delegation gate, read gate, comment nag, Stop checklist
with default gates and a 3-block cap), three shipped skills, and
eval suite structure (`claude plugin eval`, early access — not yet runnable
on this account). Remaining: knowledge-layer repos (code-graph, repo-graph)
and dogfooding.

## Requirements

`jq` and `python3` must be installed: the hooks block instead of skipping when
either is missing. The default `quality` gate for Python repos also needs
`ruff`, `coverage` and `bandit` (`plugin/claude-code/bin/doctor.sh`).

## Skills

- **`harness-pipeline`** — the core enforced protocol: SDD → strict TDD →
  subagent-only implementation → review gate → live-test → PR.
- **`live-test`** — runs the service in Docker against the real deploy
  shape and writes `.harness/live-test.md` evidence.
- **`review-gate`** — launches fresh-context transversal review via
  subagents and writes `.harness/review-report.md` evidence.

## Docs

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions.
