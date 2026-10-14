#!/usr/bin/env bats

load helpers

setup() {
  HOOK="$SCRIPTS/user-prompt-turn.sh"
  new_repo
}

teardown() {
  rm -rf "$REPO"
}

prompt_json() { jq -nc --arg p "$1" --arg sid "${2:-s1}" --arg cwd "$REPO" '{session_id: $sid, cwd: $cwd, hook_event_name: "UserPromptSubmit", prompt: $p}'; }
state() { jq -c . "$REPO/.harness/state/${1:-s1}.turn"; }

@test "a plain prompt writes a fresh state: nothing spawned, no override" {
  run_hook "$HOOK" "$(prompt_json 'fix the bug please')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(state)" = '{"spawned":0,"cap_override":null}' ]
}

@test "agents: N sets cap_override, case-insensitively and with optional spaces" {
  for p in 'yes, agents: 6' 'Agents:6' 'AGENTS:    6' 'ok.
agents: 6 and go'; do
    run_hook "$HOOK" "$(prompt_json "$p")"
    [ "$status" -eq 0 ]
    [ "$(jq -r .cap_override "$REPO/.harness/state/s1.turn")" = "6" ]
  done
}

@test "agents: without an integer, or an absurdly long one, does not break the state" {
  for p in 'agents:' 'agents: many' 'no agents here'; do
    run_hook "$HOOK" "$(prompt_json "$p")"
    [ "$(jq -r .cap_override "$REPO/.harness/state/s1.turn")" = "null" ]
  done
  run_hook "$HOOK" "$(prompt_json 'agents: 08')"
  [ "$(jq -r .cap_override "$REPO/.harness/state/s1.turn")" = "8" ]
  run_hook "$HOOK" "$(prompt_json 'agents: 99999999999999999999999')"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.cap_override | type' "$REPO/.harness/state/s1.turn")" = "number" ]
}

@test "the word workflow in a prompt is not recorded: only agents: N is consent" {
  for p in 'go with the workflow' "don't use a workflow" 'Workflow' 'ultracode'; do
    run_hook "$HOOK" "$(prompt_json "$p")"
    [ "$(state)" = '{"spawned":0,"cap_override":null}' ]
  done
}

@test "every prompt rewrites the state: the spawn count and old overrides are reset" {
  mkdir -p "$REPO/.harness/state"
  echo '{"spawned":4,"cap_override":9,"workflow_ok":true}' > "$REPO/.harness/state/s1.turn"
  run_hook "$HOOK" "$(prompt_json 'next question')"
  [ "$(state)" = '{"spawned":0,"cap_override":null}' ]
}

@test "state is per session and the session id is sanitized into the file name" {
  run_hook "$HOOK" "$(prompt_json 'agents: 3' 's2')"
  [ "$(jq -r .cap_override "$REPO/.harness/state/s2.turn")" = "3" ]
  [ ! -f "$REPO/.harness/state/s1.turn" ]
  run_hook "$HOOK" "$(prompt_json 'hi' '../evil/id')"
  [ -f "$REPO/.harness/state/___evil_id.turn" ]
}

@test "never blocks: garbage input, empty input and an unwritable state dir all exit 0 silently" {
  run_hook "$HOOK" 'not json'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run_hook "$HOOK" ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run_hook "$HOOK" '[1,2,3]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  CLAUDE_PROJECT_DIR=/dev/null/nope run_hook "$HOOK" "$(prompt_json 'agents: 2')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  chmod 500 "$REPO/.harness" 2>/dev/null || { mkdir -p "$REPO/.harness" && chmod 500 "$REPO/.harness"; }
  run_hook "$HOOK" "$(prompt_json 'agents: 2')"
  chmod 700 "$REPO/.harness"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "never blocks without jq" {
  FAKE="$(tool_path jq)"
  run_hook_with_path "$FAKE" "$HOOK" "$(prompt_json 'agents: 2')"
  rm -rf "$FAKE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "works under the macOS system bash 3.2" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$(prompt_json 'yes, agents: 6, workflow')" "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(state)" = '{"spawned":0,"cap_override":6}' ]
}
