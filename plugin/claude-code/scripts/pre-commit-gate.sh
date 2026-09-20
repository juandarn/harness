#!/usr/bin/env bash
# PreToolUse(Bash + GitHub MCP writes): denies a commit/push that carries AI attribution, skips
# hooks (--no-verify) or leaves the repo gates red. Fails closed when jq or python3 is missing.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

INPUT="$(cat)"
GIT='(^|[;&|(`{])[[:space:]]*((sudo|env|command|time|exec)[[:space:]]+)*git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?))*[[:space:]]+'
COMMIT_RE="${GIT}commit([[:space:]]|\$)"
PUSH_RE="${GIT}push([[:space:]]|\$)"

# Without jq the command cannot be parsed: deny whatever looks like a commit/push, allow the rest
# so jq itself can still be installed.
if ! command -v jq >/dev/null 2>&1; then
  RAW="$(printf '%s' "$INPUT" | tr '\n"' ';;')"
  if [[ "$RAW" =~ $COMMIT_RE || "$RAW" =~ $PUSH_RE || "$RAW" == *';mcp__'* ]]; then
    hook_block "commit/push gate needs jq and it is missing (brew install jq) — blocking instead of skipping."
  fi
  exit 0
fi
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || hook_block "hook input is not valid JSON — blocking instead of guessing."

TOOL="$(hook_field '.tool_name // empty')"
CWD="$(hook_field '.cwd // empty')"
DIR="${CWD:-$(hook_project_dir)}"
VERB=commit
TEXT=""

if [[ "$TOOL" == mcp__* ]]; then
  TEXT="$(hook_field '[.tool_input.message, .tool_input.commit_message, .tool_input.commit_title] | map(select(. != null)) | join("\n")')"
else
  CMD="$(hook_field '.tool_input.command // empty')"
  PROBE="${CMD//$'\n'/;}"
  [[ "$PROBE" =~ $COMMIT_RE || "$PROBE" =~ $PUSH_RE ]] || exit 0
  [[ "$PROBE" =~ $PUSH_RE ]] && VERB=push
  TEXT="$CMD"

  # Directory the git command runs in: `git -C <dir>` wins, then a leading `cd <dir>`.
  CD_RE='(^|[;&|][[:space:]]*)cd[[:space:]]+"?([^;&|"[:space:]]+)'
  C_RE='git[[:space:]]+-C[[:space:]]+"?([^"[:space:]]+)'
  if [[ "$PROBE" =~ $C_RE ]]; then TARGET="${BASH_REMATCH[1]}"
  elif [[ "$PROBE" =~ $CD_RE ]]; then TARGET="${BASH_REMATCH[2]}"
  else TARGET=""; fi
  if [ -n "$TARGET" ]; then
    TARGET="${TARGET/#\~/$HOME}"
    case "$TARGET" in /*) ;; *) TARGET="$DIR/$TARGET" ;; esac
    [ -d "$TARGET" ] && DIR="$TARGET"
  fi

  # `git commit -F <file>` carries its message in a file.
  F_RE='(-F|--file)[[:space:]=]+"?([^"[:space:]]+)'
  if [[ "$PROBE" =~ $F_RE ]] && [ -f "${BASH_REMATCH[2]}" ]; then TEXT="$TEXT"$'\n'"$(cat "${BASH_REMATCH[2]}")"; fi

  LOWER_CMD="$(printf '%s' "$PROBE" | tr '[:upper:]' '[:lower:]')"
  NV_RE='(^|[[:space:]])--no-verify([[:space:]=]|$)'
  HP_RE='core\.hookspath'
  if [[ "$LOWER_CMD" =~ $NV_RE || "$LOWER_CMD" =~ $HP_RE ]]; then
    hook_block "commit/push gate: --no-verify / core.hooksPath bypasses the hooks. Fix the failing check instead of skipping it."
  fi
fi

ROOT="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT" ] || ROOT="$(git -C "$(hook_project_dir)" rev-parse --show-toplevel 2>/dev/null)"

if [ "$VERB" = push ] && [ -n "$ROOT" ]; then
  TEXT="$TEXT"$'\n'"$(git -C "$ROOT" log HEAD --not --remotes -n 100 --format=%B 2>/dev/null)"
fi

LOWER="$(printf '%s' "$TEXT" | tr '[:upper:]' '[:lower:]')"
ATTR_RE='co-authored-by[[:space:]]*:|generated[[:space:]]+(with|by)[^[:alnum:]]*claude|noreply@anthropic\.com'
if [[ "$LOWER" =~ $ATTR_RE ]]; then
  hook_block "commit/push gate: message carries a Co-Authored-By trailer or AI attribution (\"${BASH_REMATCH[0]}\"). Remove it; commits are authored by the human."
fi

[ -n "$ROOT" ] || exit 0
command -v python3 >/dev/null 2>&1 || hook_block "commit/push gate needs python3 to run the repo gates and it is missing — blocking instead of skipping."

CFG="$ROOT/harness.gates.json"
[ -f "$CFG" ] || CFG="$HARNESS_ROOT/gates/default.gates.json"
LOG="$(CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$ROOT}" hook_harness_subdir logs)/pre-commit-gate.log"

if OUT="$(python3 "$HARNESS_ROOT/gates/run_gates.py" "$CFG" "$ROOT" 2>&1)"; then
  printf '%s %s green\n%s\n' "$(date -u +%FT%TZ)" "$VERB" "$OUT" > "$LOG" 2>/dev/null
  exit 0
fi
printf '%s %s RED\n%s\n' "$(date -u +%FT%TZ)" "$VERB" "$OUT" > "$LOG" 2>/dev/null
hook_block "commit/push gate: repo gates are red (full log: $LOG)
$(printf '%s' "$OUT" | tail -n 25 | cut -c1-300)"
