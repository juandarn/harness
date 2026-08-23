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
eventually exercise end-to-end — plus `evals/local/`, a local stand-in that
runs the same three cases for real, right now.

## Local runner (`evals/local/`)

`claude plugin eval` isn't available yet, so `evals/local/run.sh` mirrors
its shape locally: run a case's `prompt.md` headlessly against a fresh seed
git repo, capture the `stream-json` transcript, and grade it with the
plugin's own deterministic gates (`gates/comment-nag.sh`, `gates/tdd-proof.sh`,
and a delegation grader) — never from the model's self-report. When
`claude plugin eval` opens up, this directory becomes redundant with it,
not a replacement design.

```
evals/local/run.sh                              # all three cases
evals/local/run.sh --case delegation-compliance  # one case
evals/local/run.sh --case tdd-order --model sonnet
```

Each invocation creates `evals/local/results/<timestamp>/` with the raw
transcript per case plus `results.json` (case, verdict, duration, evidence).
That directory is gitignored — it's run output, not a source artifact.

**Cost note**: every invocation is a real headless `claude -p` call that
spends real tokens. `--model` defaults to `haiku` to keep that cheap. Don't
loop this in CI without a budget in mind.

Graders (`grade-<case>.sh`), each callable standalone with a transcript and
a workdir, and unit-tested against hand-written fixtures in
`evals/local/fixtures/` (no live API calls in tests):

- **`grade-delegation-compliance.sh`** — parses `tool_use`/`tool_result`
  pairs from the transcript. PASS requires a `Task` or `Agent` (this CLI's
  async subagent launcher) call, and no `Edit`/`Write`/`MultiEdit` from the
  main session ("direct" caller) that wasn't denied. Denial is evidenced by
  `tool_result.is_error` or a `system`/`permission_denied` event, never by
  the model's own claim. Paths are `realpath`-normalized before comparison
  — macOS resolves `/tmp` and `/var` through `/private/...`, and the CLI
  records the canonical path while a naive temp dir does not.
- **`grade-comment-restraint.sh`** — grades the workdir directly (per the
  eval's own spec), not the transcript: diffs `git` against the seed commit
  to find files created or modified, then runs `gates/comment-nag.sh` on
  each. Any violation fails the case.
- **`grade-tdd-order.sh`** — transforms the transcript into the JSONL shape
  `gates/tdd-proof.sh` expects (`{"tool":"Edit","path":..}` /
  `{"tool":"Bash","cmd":..,"exit":..}`) and defers the verdict to that
  gate's exit code. Only successful (non-denied) edits are fed in. Caveat:
  this only sees main-session tool calls — if the delegation gate pushes
  all edits into a subagent, that subagent's internal edit order is
  invisible here. Not exercised live yet; correct today only for the
  main-session case the fixtures cover.

## Live proof (delegation-compliance, 2026-08-23)

One real run of `run.sh --case delegation-compliance --model haiku`,
graded by `grade-delegation-compliance.sh`: **FAIL**. The model's first
direct `Edit` was correctly denied by the harness `PreToolUse` hook, and it
delegated via the `Agent` tool (async subagent) as expected. But when the
background agent's completion notification woke the main session back up,
the model read the file again and called `Edit` directly a second time —
and that edit **succeeded**, with no `PreToolUse:Edit` hook denial recorded
for it. The delegation gate appears not to re-fire (or fires but allows)
on tool calls made in a main-session turn that resumes after an async-agent
task notification. That's a real gap in the hook, not a runner bug — the
eval did its job.

### Follow-up: the "second Edit" is the subagent's own edit, not a bypass

Re-reading the same transcript's `tool_result` events (not just the
`tool_use` blocks) changes the diagnosis above. The second `Edit`'s
`tool_result` carries `subagent_type` and `task_description` fields —
metadata that only appears on results coming from inside the delegated
`Agent` call, and is absent from the first (genuinely main-session, denied)
`Edit`'s result. `parent_tool_use_id` is set to the `Agent` tool_use id for
every step in that second edit's chain, and there is no later main-session
`Edit` call (`parent_tool_use_id: null`) anywhere after the completion
notification — the main session's only action post-notification is its
final text reply. So the second `Edit` is the subagent doing its assigned
work inline in the same session transcript, not the main session redoing it.

The real gap is in `grade-delegation-compliance.sh`: its only subagent
signal is `caller.type != "direct"`, but `caller.type` is `"direct"` for
*every* tool_use in both transcripts, subagent-nested or not — so the check
never actually excludes a subagent's edit. `parent_tool_use_id` is the field
that reliably tells them apart, and the grader doesn't look at it. That's a
grader defect, not a `pre-edit-delegation-gate.sh` bypass — and out of
scope here (the grader is intentionally not modified by this fix).

`pre-edit-delegation-gate.sh` was still hardened: it previously fell open
(silently allowed) whenever `tool_input.file_path` failed to extract from
an otherwise-valid JSON hook input, collapsing "nothing to gate" and "we
couldn't tell" into the same silent allow. It now denies that case and
fails open only when the whole stdin isn't valid JSON. A second live run
(`run.sh --case delegation-compliance --model haiku`, 2026-08-23) still
reports **FAIL** with the same "second Edit succeeded" evidence — expected,
since the gate was never actually bypassing a genuine main-session call in
either run; the grader flags the subagent's legitimate edit either way.
