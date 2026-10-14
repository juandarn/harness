#!/usr/bin/env bash
# UserPromptSubmit: resets the session's per-turn subagent state ("agents: N" cap override,
# "workflow" go-ahead). Never blocks or prints anything.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
exec 2>/dev/null

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1 || exit 0

PROMPT="$(hook_field '.prompt // empty' | tr '[:upper:]' '[:lower:]')"

CAP=null
if [[ "$PROMPT" =~ agents:[[:space:]]*([0-9]+) ]]; then
  N="${BASH_REMATCH[1]}"
  [ "${#N}" -le 6 ] || N=999999
  CAP=$((10#$N))
fi

WORKFLOW=false
[[ "$PROMPT" =~ (^|[^[:alnum:]])workflows?([^[:alnum:]]|$) ]] && WORKFLOW=true

STATE="$(hook_turn_state)" || exit 0
TMP="$STATE.tmp.$$"
if jq -nc --argjson cap "$CAP" --argjson wf "$WORKFLOW" '{spawned:0,cap_override:$cap,workflow_ok:$wf}' > "$TMP"; then
  mv -f "$TMP" "$STATE" || rm -f "$TMP"
else
  rm -f "$TMP"
fi
exit 0
