#!/usr/bin/env bash
# PreToolUse(Bash): deny shell writes (interpreters, sed/tee, redirects into source files), so
# source edits go through Edit/Write and the TDD gate applies. Read-only commands pass. Fails closed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

hook_read_json
CMD="$(hook_field '.tool_input.command // empty')"
[ -n "$CMD" ] || exit 0

# Newlines flattened so a heredoc body is matched together with its interpreter line.
FLAT="$(printf '%s' "$CMD" | tr '\n' ' ')"

WMARK=$'(open\\(.*[\'"]w|write_text|write_bytes|shutil\\.(copy|move)|os\\.(replace|rename)|File\\.(write|open)|writeFileSync)'
INTERP="(python3?|perl|ruby|node)\\b.*(-c|-e)\\b.*($WMARK|-i\\b)"
STDIN_INTERP="(python3?|perl|ruby|node)\\b.*([[:space:]]-([[:space:]]|\$)|<<).*$WMARK"
SHELLW='(^|[^[:alnum:]_])(sed -i|perl -i|tee)([^[:alnum:]_]|$)'
SRC_EXT='\.(go|py|ts|tsx|js|jsx|kt|java|rb|sh|sql|bats)$'

# True when a > or >> redirect targets a source file (or a variable, with a heredoc present).
# Scratchpads under /tmp and /private/tmp and /dev/* targets are exempt.
redirects_source() {
  local t
  while IFS= read -r t; do
    t="${t#"${t%%[!>]*}"}"
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t//[\"\']/}"
    case "$t" in /tmp/* | /private/tmp/* | /dev/*) continue ;; esac
    printf '%s' "$t" | grep -Eq "$SRC_EXT" && return 0
    case "$t" in *'$'*) case "$CMD" in *'<<'*) return 0 ;; esac ;; esac
  done < <(printf '%s' "$FLAT" | grep -Eo '(^|[^>&])[0-9]?>>?[[:space:]]*[^[:space:]<>&|;]+' | sed -E 's/^[^>]*[0-9]?>/>/')
  return 1
}

if printf '%s' "$FLAT" | grep -Eq "$INTERP" || printf '%s' "$FLAT" | grep -Eq "$STDIN_INTERP" ||
  printf '%s' "$FLAT" | grep -Eq "$SHELLW" || redirects_source; then
  if [ -z "$(hook_field '.agent_id // empty')" ]; then
    MSG="harness: the main session does not write code or tests through Bash. Delegate to a Sonnet subagent: it writes the test first, runs only that spec, watches it FAIL, then edits with Edit/Write."
  else
    MSG="harness: file writes through Bash (interpreters, sed/tee, redirects into source files) are blocked. Use Edit or Write, test first: write the test, watch it FAIL, then edit source."
  fi
  jq -n --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$m}}'
fi
exit 0
