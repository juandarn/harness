#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit): denies a production-source edit until this session's
# .harness/state/<session_id>.jsonl records a failing test run (RED before code).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

hook_read_json
FILE="$(hook_field '.tool_input.file_path // empty')"
SID="$(hook_field '.session_id // empty')"
[ -n "$FILE" ] || hook_block "TDD gate: tool_input.file_path is missing — denying instead of guessing it is safe."
case "$FILE" in /*) ;; *) FILE="$(hook_project_dir)/$FILE" ;; esac

ROOT="$(hook_repo_root "$FILE")"
[ -n "$ROOT" ] || exit 0
hook_is_source_path "$(hook_relpath "$FILE" "$ROOT")" || exit 0

[ -n "$SID" ] || hook_block "TDD gate: session_id is missing, so the RED test run cannot be verified — denying."
STATE="$(hook_harness_subdir state)/$(hook_safe_id "$SID").jsonl"

if [ -s "$STATE" ] && jq -e -n '[inputs | select(.exit != 0 and .exit != 126 and .exit != 127)] | length > 0' "$STATE" >/dev/null 2>&1; then
  exit 0
fi

hook_block "TDD gate: no failing test run recorded this session. Write the test first, run it and watch it FAIL (RED), then edit source: $FILE"
