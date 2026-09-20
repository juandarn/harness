#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit): when the repo has an active SDD change under .harness/sdd/,
# denies production-source edits until that change has a non-empty tasks.md. No SDD dir = allow.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

hook_read_json
FILE="$(hook_field '.tool_input.file_path // empty')"
[ -n "$FILE" ] || hook_block "SDD gate: tool_input.file_path is missing — denying instead of guessing it is safe."
case "$FILE" in /*) ;; *) FILE="$(hook_project_dir)/$FILE" ;; esac

ROOT="$(hook_repo_root "$FILE")"
[ -n "$ROOT" ] || exit 0
SDD="$ROOT/.harness/sdd"
[ -d "$SDD" ] || exit 0
hook_is_source_path "$(hook_relpath "$FILE" "$ROOT")" || exit 0

# Active change = most recently modified non-archived change directory.
ACTIVE=""
for d in "$SDD"/*/; do
  [ -d "$d" ] || continue
  d="${d%/}"
  [ "${d##*/}" = "archive" ] && continue
  if [ -z "$ACTIVE" ] || [ "$d" -nt "$ACTIVE" ]; then ACTIVE="$d"; fi
done
[ -n "$ACTIVE" ] || exit 0

[ -s "$ACTIVE/tasks.md" ] && exit 0
hook_block "SDD gate: active change '${ACTIVE##*/}' has no tasks.md. Finish spec, design and tasks before editing source: $FILE"
