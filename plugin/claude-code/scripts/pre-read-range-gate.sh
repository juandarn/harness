#!/usr/bin/env bash
# PreToolUse(Read): deny a whole-file Read of a large text file once, asking for
# a ranged read instead. Everything read stays in context and is re-read on every
# later turn, so one 2k-line dump costs far more than a grep plus a 100-line slice.
# An explicit limit is allowed through: the model can still read it all on purpose.
# Opt-in with HARNESS_READ_GATE=1 (no measurable gain in evals/token yet); threshold via
# HARNESS_READ_MAX_LINES (default 400).
set -uo pipefail

[ "${HARNESS_READ_GATE:-0}" = "1" ] || exit 0
MAX="${HARNESS_READ_MAX_LINES:-400}"

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
LIMIT="$(printf '%s' "$INPUT" | jq -r '.tool_input.limit // empty' 2>/dev/null)"
[ -n "$FILE" ] && [ -z "$LIMIT" ] && [ -f "$FILE" ] || exit 0

case "$FILE" in
  *.png|*.jpg|*.jpeg|*.gif|*.webp|*.pdf|*.ipynb) exit 0 ;;
esac

LINES="$(wc -l < "$FILE" 2>/dev/null | tr -d ' ')"
[ -n "$LINES" ] && [ "$LINES" -gt "$MAX" ] || exit 0

jq -n --arg reason "harness: $FILE has $LINES lines. Grep for what you need, then Read with offset/limit (a few hundred lines at most). Pass an explicit limit only if you truly need the whole file." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
exit 0
