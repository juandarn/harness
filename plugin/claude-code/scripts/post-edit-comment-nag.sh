#!/usr/bin/env bash
# Thin PostToolUse entrypoint: extracts file_path from hook JSON on stdin,
# runs gates/comment-nag.sh, and emits a block decision if it fails.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$(cd "$SCRIPT_DIR/../gates" && pwd)/comment-nag.sh"

INPUT="$(cat)"

if command -v jq >/dev/null 2>&1; then
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')" || {
    echo "harness: comment gate cannot parse hook input — blocking instead of skipping." >&2
    exit 2
  }
elif ! command -v python3 >/dev/null 2>&1; then
  echo "harness: comment gate needs jq or python3 and neither is installed — blocking instead of skipping." >&2
  exit 2
else
  FILE_PATH="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("file_path", ""))
except Exception:
    print("")
' 2>/dev/null || true)"
fi

[ -n "$FILE_PATH" ] || exit 0
[ -f "$FILE_PATH" ] || exit 0

OUTPUT="$("$GATE" "$FILE_PATH" 2>&1)" && exit 0

REASON="$OUTPUT"
if [ "${#REASON}" -gt 500 ]; then
  REASON="${REASON:0:499}…"
fi

if command -v jq >/dev/null 2>&1; then
  jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
else
  python3 -c '
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
' "$REASON"
fi
exit 0
