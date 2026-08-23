#!/usr/bin/env bash
# Thin Stop entrypoint: runs the project's harness.gates.json (if any)
# through gates/run_gates.py and blocks session end on a failing gate.
# Opt-in per repo; silent when no gates file is present.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_GATES="$(cd "$SCRIPT_DIR/../gates" && pwd)/run_gates.py"

INPUT="$(cat)"

if command -v jq >/dev/null 2>&1; then
  STOP_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)"
  PROJECT_DIR="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
else
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(str(bool(data.get("stop_hook_active", False))).lower())
    print(data.get("cwd", "") or "")
except Exception:
    print("false")
    print("")
' 2>/dev/null)"
  STOP_ACTIVE="$(printf '%s\n' "$PARSED" | sed -n '1p')"
  PROJECT_DIR="$(printf '%s\n' "$PARSED" | sed -n '2p')"
fi

# Loop protection: already continuing from a Stop hook block, do not re-run.
[ "$STOP_ACTIVE" = "true" ] && exit 0

PROJECT_DIR="${PROJECT_DIR:-$PWD}"
GATES_FILE="$PROJECT_DIR/harness.gates.json"

# Opt-in per repo, same pattern as rigor's keel.gates.json.
[ -f "$GATES_FILE" ] || exit 0

# Script-level errors (missing runtime) fail open, not gate-result errors.
command -v python3 >/dev/null 2>&1 || exit 0
[ -f "$RUN_GATES" ] || exit 0

OUTPUT="$(python3 "$RUN_GATES" "$GATES_FILE" "$PROJECT_DIR" 2>&1)"
STATUS=$?

[ "$STATUS" -eq 0 ] && exit 0

BODY="$OUTPUT"
if [ "${#BODY}" -gt 400 ]; then
  BODY="${BODY:0:399}…"
fi
REASON="$(printf 'harness gates failed:\n%s' "$BODY")"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
else
  python3 -c '
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
' "$REASON"
fi
exit 0
