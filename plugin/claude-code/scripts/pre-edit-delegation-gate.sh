#!/usr/bin/env bash
# Thin PreToolUse entrypoint: denies direct Edit/Write/MultiEdit/NotebookEdit
# calls from the main session, forcing delegation to a subagent. Subagent
# calls (agent_id set) and non-git targets (scratchpads) pass through.
set -uo pipefail

INPUT="$(cat)"

deny() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg reason "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  else
    python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": sys.argv[1]}}))
' "$reason"
  fi
}

# Whole stdin isn't valid JSON -> nothing we can safely evaluate, fail open.
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0
else
  printf '%s' "$INPUT" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 || exit 0
fi

if command -v jq >/dev/null 2>&1; then
  AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)"
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
else
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print(data.get("agent_id", "") or "")
print((data.get("tool_input") or {}).get("file_path", "") or "")
' 2>/dev/null)"
  AGENT_ID="$(printf '%s\n' "$PARSED" | sed -n '1p')"
  FILE_PATH="$(printf '%s\n' "$PARSED" | sed -n '2p')"
fi

# Global opt-out: inline editing costs less than a subagent reloading the full system prompt.
[ "${HARNESS_INLINE_OK:-}" = "1" ] && exit 0

# Subagent call -> always allowed. agent_type is unreliable, agent_id is not.
[ -n "$AGENT_ID" ] && exit 0

# Valid JSON but file_path didn't extract -> deny, don't assume it's safe.
if [ -z "$FILE_PATH" ]; then
  deny "harness: PreToolUse input parsed but tool_input.file_path was missing — denying instead of guessing it's safe."
  exit 0
fi

DIR="$(dirname -- "$FILE_PATH")"
[ -d "$DIR" ] || exit 0

# Not inside a git repo (scratchpad, temp file) -> allow.
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

REPO_ROOT="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || exit 0

# Per-repo opt-out, meant to be gitignored.
[ -f "$REPO_ROOT/.harness-inline-ok" ] && exit 0

deny "harness: the main session does not edit code — delegate to a subagent (Sonnet). This repo enforces orchestrator-only mode."
exit 0
