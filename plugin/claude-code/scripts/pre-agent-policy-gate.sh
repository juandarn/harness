#!/usr/bin/env bash
# PreToolUse(Agent|Task|Workflow): opt-in subagent policy (Workflow needs "agents: N", subagents
# need an allowed model, each turn has a spawn cap). Does nothing unless a knob is set.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

MODELS_RE="${HARNESS_SUBAGENT_MODELS:-}"
CAP_KNOB="${HARNESS_MAX_AGENTS_PER_TURN:-}"
[[ "$CAP_KNOB" =~ ^0+$ ]] && CAP_KNOB=""
[ "${HARNESS_WORKFLOW_GATE:-}" = 1 ] || [ -n "$MODELS_RE" ] || [ -n "$CAP_KNOB" ] || exit 0

hook_read_json
TOOL="$(hook_field '.tool_name // empty')"
STATE="$(hook_turn_state)" || STATE=""
COST='stating "N agents, rough cost"; they approve'

if [ "$TOOL" = Workflow ]; then
  [ "${HARNESS_WORKFLOW_GATE:-}" = 1 ] || exit 0
  if [ -n "$STATE" ] && [ -f "$STATE" ] && jq -e '(.cap_override | type) == "number" and .cap_override >= 1' "$STATE" >/dev/null 2>&1; then exit 0; fi
  hook_decision deny "harness: Workflow needs the user's explicit go. Ask first, $COST by replying with \"agents: N\". Ultracode alone is not consent."
fi
case "$TOOL" in Agent|Task) ;; *) exit 0 ;; esac

if [ -n "$MODELS_RE" ]; then
  MODEL="$(hook_field '.tool_input.model // empty')"
  HINT="Code goes to sonnet, writing and paperwork to haiku."
  [ "$(hook_field '.tool_input.subagent_type // empty')" = fork ] \
    && hook_decision deny "harness: a fork subagent inherits the main session's model. Spawn a typed subagent with an explicit model (allowed: $MODELS_RE). $HINT"
  [ -n "$MODEL" ] || hook_decision deny "harness: set an explicit model on every subagent call (allowed: $MODELS_RE). $HINT"
  printf '%s' "$MODEL" | grep -Eiq -- "$MODELS_RE" 2>/dev/null \
    || hook_decision deny "harness: subagent model \"$MODEL\" is not allowed (allowed: $MODELS_RE). $HINT"
fi

[ -n "$CAP_KNOB" ] || exit 0
[[ "$CAP_KNOB" =~ ^[0-9]{1,9}$ ]] || hook_decision deny "harness: HARNESS_MAX_AGENTS_PER_TURN must be an integer (got \"$CAP_KNOB\")."
[ -n "$STATE" ] || hook_decision deny "harness: cannot record subagent spawns (.harness/state is not writable) — denying instead of guessing."

LOCK="$STATE.lock"
TRIES=0
until mkdir "$LOCK" 2>/dev/null; do
  find "$LOCK" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2>/dev/null
  TRIES=$((TRIES + 1))
  [ "$TRIES" -le 30 ] || hook_decision deny "harness: could not take the subagent counter lock ($LOCK) — retry the call."
  sleep 0.1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

SPAWNED=0
OVERRIDE=0
if [ -e "$STATE" ]; then
  read -r SPAWNED OVERRIDE < <(jq -r '"\(.spawned // 0) \(.cap_override // 0)"' "$STATE" 2>/dev/null)
  [[ "$SPAWNED" =~ ^[0-9]{1,9}$ && "$OVERRIDE" =~ ^[0-9]{1,9}$ ]] \
    || hook_decision deny "harness: subagent counter state $STATE is unreadable — denying instead of guessing."
fi

CAP=$((10#$CAP_KNOB))
[ $((10#$OVERRIDE)) -le "$CAP" ] || CAP=$((10#$OVERRIDE))
SPAWNED=$((10#$SPAWNED))
if [ "$SPAWNED" -ge "$CAP" ]; then
  hook_decision deny "harness: subagent cap reached ($SPAWNED of $CAP this turn). Ask the user first, $COST by replying with \"agents: N\"."
fi

NEW="$STATE.tmp.$$"
if [ -e "$STATE" ]; then
  jq -c '.spawned = ((.spawned // 0) + 1)' "$STATE" > "$NEW" 2>/dev/null
else
  jq -nc '{spawned:1,cap_override:null}' > "$NEW" 2>/dev/null
fi && mv -f "$NEW" "$STATE" 2>/dev/null || { rm -f "$NEW"; hook_decision deny "harness: could not record the subagent spawn in $STATE — denying instead of guessing."; }
exit 0
