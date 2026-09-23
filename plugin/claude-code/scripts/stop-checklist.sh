#!/usr/bin/env bash
# Stop hook: runs the repo's harness.gates.json and blocks session end while a gate is red.
# Repos with no harness.gates.json exit silently (no implicit default gates on Stop).
# A per-session counter caps blocks at 3 so a broken gate cannot trap the session forever.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

MAX_BLOCKS=3
INPUT="$(cat)"

SID=""; CWD=""
if command -v jq >/dev/null 2>&1; then
  SID="$(hook_field '.session_id // empty')"
  CWD="$(hook_field '.cwd // empty')"
elif command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("session_id", "") or "")
    print(d.get("cwd", "") or "")
except Exception:
    print(); print()
' 2>/dev/null)"
  SID="$(printf '%s\n' "$PARSED" | sed -n '1p')"
  CWD="$(printf '%s\n' "$PARSED" | sed -n '2p')"
fi
SID="${SID:-nosession}"
CWD="${CWD:-$PWD}"
ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
ROOT="${ROOT:-$CWD}"

COUNTER="$(CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}" hook_harness_subdir state)/$(hook_safe_id "$SID").stop-blocks"

block() {
  local n
  n="$(cat "$COUNTER" 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -ge "$MAX_BLOCKS" ]; then
    printf 'harness: stop blocked %s times this session; releasing.\n' "$MAX_BLOCKS" >&2
    exit 0
  fi
  printf '%s' "$((n + 1))" > "$COUNTER"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg reason "$1" '{decision: "block", reason: $reason}'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys; print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' "$1"
  else
    printf 'harness: %s\n' "$1" >&2
    exit 2
  fi
  exit 0
}

command -v jq >/dev/null 2>&1 || block "harness gates cannot run: jq is missing (brew install jq)."
command -v python3 >/dev/null 2>&1 || block "harness gates cannot run: python3 is missing."

GATES_FILE="$ROOT/harness.gates.json"
[ -f "$GATES_FILE" ] || exit 0
[ -f "$HARNESS_ROOT/gates/run_gates.py" ] || block "harness gates cannot run: gates/run_gates.py is missing from the plugin."

OUTPUT="$(python3 "$HARNESS_ROOT/gates/run_gates.py" "$GATES_FILE" "$ROOT" 2>&1)"
[ "$?" -eq 0 ] && exit 0

BODY="$OUTPUT"
if [ "${#BODY}" -gt 1500 ]; then
  BODY="${BODY:0:1499}…"
fi
block "$(printf 'harness gates failed:\n%s' "$BODY")"
