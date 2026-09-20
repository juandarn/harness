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
config copies) also goes to Sonnet. This keeps the orchestrator's context clean
and forces every code change through a reviewable, delegated step.

## 4. Hooks

Every hook is default-on and fails closed: a hook that cannot parse its input,
or that needs `jq` / `python3` and cannot find it, blocks (exit 2) instead of
skipping. Shared helpers live in `scripts/hook-lib.sh`. Runtime state and logs
go under `${CLAUDE_PROJECT_DIR}/.harness/` (`state/`, `logs/`, `sdd/`).

- **Commit/push gate** (`pre-commit-gate.sh`; PreToolUse on Bash and on the
  GitHub MCP writes `push_files`, `create_or_update_file`,
  `merge_pull_request`): denies Co-Authored-By trailers and AI attribution
  (including heredocs, `-F` files and unpushed commits on push), `--no-verify`
  and `core.hooksPath` overrides, and any commit/push while the repo gates are
  red. Log: `.harness/logs/pre-commit-gate.log`.
- **TDD order gate** (`pre-edit-tdd-gate.sh` + `post-bash-test-recorder.sh`):
  the recorder appends every test-runner run and its exit code to
  `.harness/state/<session_id>.jsonl` (PostToolUse and PostToolUseFailure).
  Edits to production source are denied until that session has a failing run
  (exit codes 126/127 and interrupts do not count). Tests, docs and config
  paths are exempt.
- **SDD artifact gate** (`pre-edit-sdd-gate.sh`): when `.harness/sdd/` holds an
  active change (newest directory, `archive/` ignored) without a non-empty
  `tasks.md`, source edits are denied.
- **Delegation gate** (Edit/Write/MultiEdit/NotebookEdit, main session): denies
  direct code edits in the orchestrator session. The only opt-out is a
  per-repo `.harness-inline-ok` file; the `HARNESS_INLINE_OK` environment
  variable no longer exists.
- **Read gate** (`pre-read-range-gate.sh`): default on; `HARNESS_READ_GATE=0`
  disables it.
- **Comment nag** (PostToolUse): blocks a comment run of 4 or more consecutive
  lines (shebangs excluded, no header exemption).
- **Stop hook checklist**: runs the repo's `harness.gates.json`, or
  `gates/default.gates.json` when the repo has none, and blocks session end
  while a blocking gate fails. Blocks are counted per session in
  `.harness/state/` and capped at 3; after the third the session may end.
- **Design gate** (`gates/design-gate.sh`, opt-in via `harness.gates.json`):
  runs Impeccable's deterministic detector rules over frontend files. Fails
  open with an install notice when impeccable is missing.

### Default gates

`gates/default.gates.json` applies to repos without their own
`harness.gates.json`: `tests` (auto-detects go, npm, gradle, mvn, cargo,
pytest, bats; a detected runner with a missing tool blocks), `comment-restraint`
(comment-nag over files changed vs HEAD) and `quality`
(`gates/quality-pipeline.sh`: format, lint, test, coverage, duplication,
security through `adapters/<stack>/adapter.sh`; only `py` ships today, other
stacks report that no adapter applies). Thresholds are pinned in
`harness.toolchain.yaml`; `bin/doctor.sh` lists missing tools, and a missing
tool blocks the gate instead of skipping it. A repo overrides the defaults by
shipping its own `harness.gates.json`; see `examples/money/` for a full one.

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
