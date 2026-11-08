#!/usr/bin/env bash
# PreToolUse(Bash): deny shell one-liners that write files, so source edits go through
# Edit/Write and the TDD gate applies. Read-only one-liners pass. Fails closed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

hook_read_json
CMD="$(hook_field '.tool_input.command // empty')"
[ -n "$CMD" ] || exit 0

INTERP=$'(python3?|perl|ruby|node)\\b.*(-c|-e)\\b.*(open\\(.*[\'"]w|write_text|write_bytes|shutil\\.(copy|move)|os\\.(replace|rename)|-i\\b)'
SHELLW='(^|[^[:alnum:]_])(sed -i|perl -i|tee)([^[:alnum:]_]|$)'

if printf '%s' "$CMD" | grep -Eq "$INTERP" || printf '%s' "$CMD" | grep -Eq "$SHELLW"; then
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"harness: file writes through python/sed/perl/tee one-liners are blocked. Use Edit or Write so the TDD gate applies."}}'
fi
exit 0
