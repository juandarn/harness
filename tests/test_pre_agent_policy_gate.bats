#!/usr/bin/env bats

load helpers

setup() {
  unset HARNESS_WORKFLOW_GATE HARNESS_SUBAGENT_MODELS HARNESS_MAX_AGENTS_PER_TURN
  GATE="$SCRIPTS/pre-agent-policy-gate.sh"
  TURN="$SCRIPTS/user-prompt-turn.sh"
  new_repo
}

teardown() {
  rm -rf "$REPO" "${FAKE:-}"
}

call_json() { jq -nc --arg t "$1" --arg sid "${3:-s1}" --arg cwd "$REPO" --argjson i "${2:-null}" '{session_id: $sid, tool_name: $t, cwd: $cwd, tool_input: ($i // {})}'; }
agent() { run_hook "$GATE" "$(call_json Agent "$(jq -nc --arg m "$1" '{subagent_type: "general-purpose", prompt: "x", model: $m}')" "${2:-s1}")"; }
say() { run_hook "$TURN" "$(jq -nc --arg p "$1" --arg sid "${2:-s1}" --arg cwd "$REPO" '{session_id: $sid, cwd: $cwd, prompt: $p}')"; }
decision() { echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
reason() { echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
allowed() { [ "$status" -eq 0 ] && [ -z "$output" ]; }
state_file() { echo "$REPO/.harness/state/${1:-s1}.turn"; }

@test "with no knob set every call passes untouched, even malformed input" {
  agent ""
  allowed
  run_hook "$GATE" "$(call_json Workflow)"
  allowed
  run_hook "$GATE" "$(call_json Agent '{"subagent_type":"fork"}')"
  allowed
  run_hook "$GATE" 'not json'
  allowed
  export HARNESS_WORKFLOW_GATE=0 HARNESS_SUBAGENT_MODELS="" HARNESS_MAX_AGENTS_PER_TURN=0
  run_hook "$GATE" "$(call_json Workflow)"
  allowed
  agent ""
  allowed
  [ ! -e "$(state_file)" ]
}

@test "with no knob set the gate does not even need jq" {
  FAKE="$(tool_path jq)"
  run_hook_with_path "$FAKE" "$GATE" "$(call_json Workflow)"
  [ "$status" -eq 0 ]
  run env -i HOME="$HOME" PATH="$FAKE" HARNESS_WORKFLOW_GATE=1 bash -c 'printf "%s" "$1" | bash "$2"' _ "$(call_json Workflow)" "$GATE"
  [ "$status" -eq 2 ]
}

@test "with a knob set, unparseable input fails closed" {
  export HARNESS_MAX_AGENTS_PER_TURN=3
  run_hook "$GATE" 'not json'
  [ "$status" -eq 2 ]
}

@test "tools other than Agent, Task and Workflow pass untouched even with every knob set" {
  export HARNESS_WORKFLOW_GATE=1 HARNESS_SUBAGENT_MODELS='^(sonnet|haiku)$' HARNESS_MAX_AGENTS_PER_TURN=1
  run_hook "$GATE" "$(call_json Bash '{"command":"ls"}')"
  allowed
}

@test "HARNESS_WORKFLOW_GATE=1 denies Workflow without the user's go and names the rule" {
  export HARNESS_WORKFLOW_GATE=1
  run_hook "$GATE" "$(call_json Workflow)"
  [ "$status" -eq 0 ]
  [ "$(decision)" = "deny" ]
  [ "$(reason)" = 'harness: Workflow needs the user'"'"'s explicit go. Ask first, stating "N agents, rough cost"; they approve by replying with "agents: N". Ultracode alone is not consent.' ]
}

@test "mentioning a workflow in the prompt does not unlock Workflow" {
  export HARNESS_WORKFLOW_GATE=1
  for p in 'ultracode' "don't use a workflow" 'run the workflow' 'workflows are fine' 'agents: none'; do
    say "$p"
    run_hook "$GATE" "$(call_json Workflow)"
    [ "$(decision)" = "deny" ]
  done
}

@test "HARNESS_WORKFLOW_GATE=1 allows Workflow when the prompt carries agents: N (N >= 1), until the next prompt" {
  export HARNESS_WORKFLOW_GATE=1
  say 'yes, agents: 4'
  run_hook "$GATE" "$(call_json Workflow)"
  allowed
  say 'agents: 1'
  run_hook "$GATE" "$(call_json Workflow)"
  allowed
  say 'agents: 0'
  run_hook "$GATE" "$(call_json Workflow)"
  [ "$(decision)" = "deny" ]
  say 'agents: 4'
  say 'thanks'
  run_hook "$GATE" "$(call_json Workflow)"
  [ "$(decision)" = "deny" ]
}

@test "the workflow go-ahead is per session" {
  export HARNESS_WORKFLOW_GATE=1
  say 'agents: 4' s1
  run_hook "$GATE" "$(call_json Workflow null s1)"
  allowed
  run_hook "$GATE" "$(call_json Workflow null s2)"
  [ "$(decision)" = "deny" ]
}

@test "the workflow gate does not touch Agent calls, and the model knob does not touch Workflow" {
  export HARNESS_WORKFLOW_GATE=1
  agent ""
  allowed
  unset HARNESS_WORKFLOW_GATE
  export HARNESS_SUBAGENT_MODELS='^(sonnet|haiku)$' HARNESS_MAX_AGENTS_PER_TURN=1
  run_hook "$GATE" "$(call_json Workflow)"
  allowed
}

@test "HARNESS_SUBAGENT_MODELS denies a fork, even one with an allowed model" {
  export HARNESS_SUBAGENT_MODELS='^(sonnet|haiku)$'
  for t in Agent Task; do
    run_hook "$GATE" "$(call_json "$t" '{"subagent_type":"fork","model":"sonnet","prompt":"x"}')"
    [ "$(decision)" = "deny" ]
    [[ "$(reason)" == *"fork"* && "$(reason)" == *"model"* ]]
  done
}

@test "HARNESS_SUBAGENT_MODELS denies a missing or empty model and says what is allowed" {
  export HARNESS_SUBAGENT_MODELS='^(sonnet|haiku)$'
  agent ""
  [ "$(decision)" = "deny" ]
  [[ "$(reason)" == *'^(sonnet|haiku)$'* && "$(reason)" == *"sonnet"* && "$(reason)" == *"haiku"* ]]
  run_hook "$GATE" "$(call_json Agent '{"subagent_type":"general-purpose","prompt":"x"}')"
  [ "$(decision)" = "deny" ]
  run_hook "$GATE" "$(call_json Task '{"prompt":"x"}')"
  [ "$(decision)" = "deny" ]
}

@test "HARNESS_SUBAGENT_MODELS denies a model that does not match and allows the ones that do" {
  export HARNESS_SUBAGENT_MODELS='^(sonnet|haiku)$'
  agent opus
  [ "$(decision)" = "deny" ]
  [[ "$(reason)" == *'"opus"'* ]]
  agent claude-sonnet-5-5
  [ "$(decision)" = "deny" ]
  for m in sonnet haiku Sonnet HAIKU; do
    agent "$m"
    allowed
  done
  run_hook "$GATE" "$(call_json Task '{"model":"haiku","prompt":"x"}')"
  allowed
}

@test "an invalid HARNESS_SUBAGENT_MODELS regex fails closed" {
  export HARNESS_SUBAGENT_MODELS='('
  agent sonnet
  [ "$(decision)" = "deny" ]
}

@test "HARNESS_MAX_AGENTS_PER_TURN allows the cap and denies the next call with the exact reason" {
  export HARNESS_MAX_AGENTS_PER_TURN=3
  say 'go'
  for _ in 1 2 3; do
    agent sonnet
    allowed
  done
  agent sonnet
  [ "$status" -eq 0 ]
  [ "$(decision)" = "deny" ]
  [ "$(reason)" = 'harness: subagent cap reached (3 of 3 this turn). Ask the user first, stating "N agents, rough cost"; they approve by replying with "agents: N".' ]
}

@test "the cap counts Agent and Task together and works without a recorded prompt" {
  export HARNESS_MAX_AGENTS_PER_TURN=2
  agent sonnet
  allowed
  [ "$(jq -c . "$(state_file)")" = '{"spawned":1,"cap_override":null}' ]
  run_hook "$GATE" "$(call_json Task '{"prompt":"x"}')"
  allowed
  agent sonnet
  [ "$(decision)" = "deny" ]
}

@test "agents: N in the prompt raises the cap for that turn" {
  export HARNESS_MAX_AGENTS_PER_TURN=3
  say 'yes, agents: 5'
  for _ in 1 2 3 4 5; do
    agent sonnet
    allowed
  done
  agent sonnet
  [ "$(decision)" = "deny" ]
  [[ "$(reason)" == *"(5 of 5 this turn)"* ]]
}

@test "an agents: N below the knob does not lower the cap" {
  export HARNESS_MAX_AGENTS_PER_TURN=3
  say 'agents: 1'
  for _ in 1 2 3; do
    agent sonnet
    allowed
  done
  agent sonnet
  [ "$(decision)" = "deny" ]
}

@test "a new prompt resets the count and the override" {
  export HARNESS_MAX_AGENTS_PER_TURN=2
  say 'agents: 3'
  for _ in 1 2 3; do agent sonnet; allowed; done
  agent sonnet
  [ "$(decision)" = "deny" ]
  say 'next'
  agent sonnet
  allowed
  agent sonnet
  allowed
  agent sonnet
  [ "$(decision)" = "deny" ]
  [[ "$(reason)" == *"(2 of 2 this turn)"* ]]
}

@test "calls denied by the model check do not consume the cap" {
  export HARNESS_SUBAGENT_MODELS='^(sonnet|haiku)$' HARNESS_MAX_AGENTS_PER_TURN=2
  say 'go'
  for _ in 1 2 3; do
    agent opus
    [ "$(decision)" = "deny" ]
    [[ "$(reason)" != *"cap"* ]]
  done
  agent haiku
  allowed
  agent sonnet
  allowed
  agent haiku
  [[ "$(reason)" == *"cap reached"* ]]
}

@test "the cap is per session" {
  export HARNESS_MAX_AGENTS_PER_TURN=1
  agent sonnet s1
  allowed
  agent sonnet s2
  allowed
  agent sonnet s1
  [ "$(decision)" = "deny" ]
}

@test "an empty or zero cap means no cap, a non-numeric one fails closed" {
  export HARNESS_SUBAGENT_MODELS='^sonnet$'
  for v in "" 0; do
    export HARNESS_MAX_AGENTS_PER_TURN="$v"
    for _ in 1 2 3 4 5; do agent sonnet; allowed; done
  done
  export HARNESS_MAX_AGENTS_PER_TURN=lots
  agent sonnet
  [ "$(decision)" = "deny" ]
  [[ "$(reason)" == *"HARNESS_MAX_AGENTS_PER_TURN"* ]]
}

@test "Workflow calls do not consume the cap" {
  export HARNESS_WORKFLOW_GATE=1 HARNESS_MAX_AGENTS_PER_TURN=1
  say 'agents: 1'
  run_hook "$GATE" "$(call_json Workflow)"
  allowed
  agent sonnet
  allowed
  agent sonnet
  [ "$(decision)" = "deny" ]
}

@test "parallel Agent calls never exceed the cap" {
  export HARNESS_MAX_AGENTS_PER_TURN=3
  say 'go'
  for i in 1 2 3 4 5 6 7 8; do
    ( printf '%s' "$(call_json Agent '{"model":"sonnet"}')" | "$GATE" > "$REPO/out$i" 2>&1 ) &
  done
  wait
  [ "$(cat "$REPO"/out? | grep -c '"deny"')" = "5" ]
  [ "$(jq -r .spawned "$(state_file)")" = "3" ]
  [ ! -d "$(state_file).lock" ]
}

@test "a stale lock is broken, a fresh one that never frees fails closed" {
  export HARNESS_MAX_AGENTS_PER_TURN=3
  say 'go'
  mkdir "$(state_file).lock"
  touch -t 202001010000 "$(state_file).lock"
  agent sonnet
  allowed
  mkdir "$(state_file).lock"
  agent sonnet
  [ "$(decision)" = "deny" ]
  [[ "$(reason)" == *"lock"* ]]
}

@test "an unreadable state file fails closed" {
  export HARNESS_MAX_AGENTS_PER_TURN=3
  say 'go'
  echo 'garbage' > "$(state_file)"
  agent sonnet
  [ "$(decision)" = "deny" ]
  export HARNESS_WORKFLOW_GATE=1
  run_hook "$GATE" "$(call_json Workflow)"
  [ "$(decision)" = "deny" ]
}

@test "works under the macOS system bash 3.2" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  export HARNESS_MAX_AGENTS_PER_TURN=1
  run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$(call_json Agent '{"model":"sonnet"}')" "$GATE"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$(call_json Agent '{"model":"sonnet"}')" "$GATE"
  [ "$(decision)" = "deny" ]
}
