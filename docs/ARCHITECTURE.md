# Architecture

## 1. Deterministic detection, surgical correction

Detection is scripted and deterministic: a hook or script checks a fact (does
a diff touch code without a subagent, is there a comment block over 3 lines,
did tests run) and signals pass/fail. It never edits code itself. Correction,
when needed, stays a model action — surgical, scoped to what the detector
flagged. Detectors signal; they don't rewrite.

## 2. Enforcement over instruction

Markdown instructions are prevention: they reduce the odds of a mistake by
telling the model what to do. They are not enforcement — a model can ignore
or forget them under context pressure. The rules that must always hold live
in hooks and evals, which run outside the model's discretion. Markdown sets
expectations; hooks and evals are the gate.

## 3. Enforced pipeline

SDD → strict TDD → apply via subagents only → transversal review gate →
live test in Docker replicating the deploy environment → PR.

The orchestrator model never writes code directly. Code implementation is
delegated to Sonnet subagents; purely mechanical work (renames, boilerplate,
config copies) may go to Haiku. This keeps the orchestrator's context clean
and forces every code change through a reviewable, delegated step.

## 4. Hooks (Fase 2)

- **PreToolUse delegation gate** (Edit/Write/MultiEdit/NotebookEdit, main
  session): denies direct code edits in the orchestrator session, forcing
  delegation to a subagent. Subagent calls and non-git targets pass through.
- **PostToolUse comment nag**: flags diffs with more than 3 consecutive
  comment lines and returns a short correction message; the model trims it.
- **Stop hook checklist**: runs `harness.gates.json` (opt-in per repo) via
  `gates/run_gates.py` and blocks session end when a blocking gate fails.
  See `docs/examples/harness.gates.json` for a sample (tests, review
  evidence, live-test evidence).
- **SDD artifact gate**: still planned — will block `apply` from starting
  without a spec/design/tasks artifact present.

## 5. Composition, not reimplementation

harness composes existing tools instead of rebuilding them:

- **rawcode** — persona, `tdd-gate`, `bench`.
- **Gentleman SDD stack** — skills and agents for the SDD workflow.
- **Engram** — persistent memory across sessions.

harness wires these together and adds the enforcement layer (hooks, gates,
evals) that makes the composed workflow mandatory instead of optional.

## 6. Knowledge layer

A separate, local-only concern (never deployed, no production dependency):

- **code-graph CLI** — static analysis over SCIP indexers, stored in SQLite
  with FTS5 and identifier tokenization. Regenerated via git hooks.
- **repo-graph** — edges derived from manifests, contracts, queues, Kingdom
  API, and Datadog APM.

Both are served to sessions through a local stdio MCP server. The AI queries
the graph; it never builds it — graph generation is deterministic tooling,
not a model task.

## 7. Packaging

- No `version` field in either `marketplace.json` or `plugin.json`. Version
  resolves to the git commit SHA, so every push is a new version.
- Marketplace auto-update must be enabled manually per machine (`/plugin` →
  Marketplaces → harness → Enable auto-update) — there is no global default.
- Plugin-thin convention, borrowed from Engram: scripts under `scripts/` are
  thin wrappers; real logic lives in testable binaries/scripts, not inline
  in hook configs.
