---
name: transversal-review
description: "Trigger: \"review transversal\", \"transversal review\", \"cross-repo review\", or once every PR of a multi-PR change is open. Runs ONE fresh-context reviewer across the whole PR set for the contracts between them, then verifies and fixes what it finds."
---

## Why

Each PR can be correct alone and the set still broken: one side sends a
name where the other decodes a UUID. `review-gate` reviews one diff; this
reviews the seams. CI cannot see them.

## When

After all PRs in the set are open, before announcing them. One reviewer
over the whole set, not one per PR.

## Procedure

1. **Launch one read-only reviewer** on Sonnet, in fresh context. Give it
   the code, not your conclusions. The brief must carry:
   - Every PR with its worktree and diff command:
     `git -C <worktree> diff origin/<base>...HEAD`.
   - The services the PRs talk to, including ones **not in the set**, and
     where their source lives (`gh api` or a local clone). A contract is
     checked against the consumer's real code, never against the producer's
     assumptions.
   - The concrete contracts to check, named per change. Walk this list and
     keep what applies:
     - Payload shape: field names, types, required fields, strict decoding,
       `omitempty` versus null.
     - Enum and action strings, route regexes, DB constraints on both sides.
     - Headers, auth, timeouts and size limits.
     - Text one side emits that a prompt or parser on the other reacts to.
     - Secrets and PII crossing the boundary.
     - Deploy order: which side must ship first, and flag or variable needs.
   - The rules: do not edit, commit, comment on PRs or post anywhere; run
     only single-package tests, never a full suite.
   - The output: at most 12 lines. Each finding as severity, `file:line`,
     the concrete failure scenario and the fix; or "no confirmed defects".
     Confirmed defects only. List the contracts it could not verify.
2. **Verify every finding yourself** before fixing: read the consumer's
   real definition. A reviewer's claim is a lead, not a fact. Keep the
   unverified contracts visible; do not report them as passing.
3. **Fix through a Sonnet subagent**, one commit per repo on the existing
   branches: failing test first, watch it FAIL, then edit with Edit/Write;
   run only the touched packages; push. No AI attribution in commits.
4. **Resolve every finding**: fixed or explicitly waived by the user.
   Never drop one silently, never waive it yourself.
5. **Recheck CI on the new heads** with `gh pr checks`. A green result from
   before the fix push does not count. Announce only after it is green.

One review round. Do not re-review the fixes unless one changed a contract.

Two blind reviewers is a different tool: use `judgment-day` only when the user asks for a dual review.
