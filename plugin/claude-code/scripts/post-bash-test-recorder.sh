#!/usr/bin/env bash
# PostToolUse / PostToolUseFailure (Bash): appends every test-runner invocation and its exit code
# to .harness/state/<session_id>.jsonl, the evidence pre-edit-tdd-gate.sh checks.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

hook_read_json
CMD="$(hook_field '.tool_input.command // empty')"
SID="$(hook_field '.session_id // empty')"
[ -n "$CMD" ] && [ -n "$SID" ] || exit 0

TEST_RE='(^|[^[:alnum:]_-])(go test|pytest|py\.test|python3? -m (pytest|unittest)|vitest|jest|mocha|bats|rspec|phpunit|cargo (test|nextest)|dotnet test|swift test|ctest|make test|(npm|pnpm|yarn|bun)( run)? test|(\./)?gradlew? [^;&|]*test|mvn [^;&|]*test)([^[:alnum:]_-]|$)'
[[ "$CMD" =~ $TEST_RE ]] || exit 0

# Exit code: explicit field when the runtime provides one, else the number in a failure payload
# ("Exit code N" / "status code N"), else 1 for a failure and 0 for a success. Interrupts prove nothing.
CODE="$(printf '%s' "$INPUT" | jq -r '
  (.tool_response // {}) as $r
  | if (.is_interrupt // false) or (($r | type) == "object" and ($r.interrupted // false)) then "skip"
    else
      (if ($r | type) == "object" then ($r.exit_code // $r.exitCode // $r.returncode // null) else null end) as $c
      | if $c != null then $c
        elif .hook_event_name == "PostToolUseFailure" or ((.error // null) != null) or (($r | type) == "object" and ($r.is_error // false)) then
          ((.error // ($r | tostring)) | capture("(?i)(exit code|status code|exit status)[: ]*(?<n>[0-9]+)")? | .n | tonumber) // 1
        else 0 end
    end' 2>/dev/null)"
case "$CODE" in ""|skip) exit 0 ;; esac

# A pipe (`go test | tail`) makes the exit code the last stage's, so a failing run reads as 0.
# For a piped command that "succeeded", trust unmistakable failure markers in the output instead.
if [ "$CODE" = "0" ] && [[ "$CMD" == *"|"* ]]; then
  OUT="$(printf '%s' "$INPUT" | jq -r '(.tool_response // empty) | if type == "string" then . elif type == "object" then ([.stdout, .output, .stderr] | map(select(type == "string")) | join("\n")) else empty end' 2>/dev/null)"
  if printf '%s\n' "$OUT" | grep -Eq '^(--- FAIL|FAIL($|[[:space:]])|FAILED|not ok )|(^|[^[:alnum:]_])[0-9]+ failed|FAILED( |\.|$)|test result: FAILED'; then
    CODE=1
  fi
fi

STATE="$(hook_harness_subdir state)/$(hook_safe_id "$SID").jsonl" || exit 0
jq -cn --arg cmd "$CMD" --argjson exit "$CODE" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{ts: $ts, cmd: $cmd, exit: $exit}' >> "$STATE"
exit 0
