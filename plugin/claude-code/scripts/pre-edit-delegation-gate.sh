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

if command -v jq >/dev/null 2>&1; then
  AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)"
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
else
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("agent_id", "") or "")
    print(data.get("tool_input", {}).get("file_path", "") or "")
except Exception:
    print("")
    print("")
' 2>/dev/null)"
  AGENT_ID="$(printf '%s\n' "$PARSED" | sed -n '1p')"
  FILE_PATH="$(printf '%s\n' "$PARSED" | sed -n '2p')"
fi

# Subagent call -> always allowed. agent_type is unreliable, agent_id is not.
[ -n "$AGENT_ID" ] && exit 0

# No target file to gate -> allow.
[ -n "$FILE_PATH" ] || exit 0

DIR="$(dirname -- "$FILE_PATH")"
[ -d "$DIR" ] || exit 0

# Not inside a git repo (scratchpad, temp file) -> allow.
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

REPO_ROOT="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || exit 0

# Per-repo opt-out, meant to be gitignored.
[ -f "$REPO_ROOT/.harness-inline-ok" ] && exit 0

deny "harness: the main session does not edit code — delegate to a subagent (code work → Sonnet; mechanical edits → Haiku). This repo enforces orchestrator-only mode."
exit 0
