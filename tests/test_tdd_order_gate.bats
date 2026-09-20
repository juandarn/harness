#!/usr/bin/env bats

load helpers

setup() {
  GATE="$SCRIPTS/pre-edit-tdd-gate.sh"
  RECORDER="$SCRIPTS/post-bash-test-recorder.sh"
  new_repo
  mkdir -p "$REPO/src" "$REPO/tests" "$REPO/docs"
}

teardown() {
  rm -rf "$REPO" "${OUTSIDE:-}" "${FAKE:-}"
}

edit_json() { jq -n --arg fp "$1" --arg sid "${2:-s1}" --arg tool "${3:-Edit}" '{session_id: $sid, tool_name: $tool, tool_input: {file_path: $fp}}'; }
bash_result_json() {
  local sid=s1 ev=PostToolUse
  case "${3:-}" in PostTool*) ev="$3" ;; ?*) sid="$3" ;; esac
  jq -n --arg c "$1" --arg sid "$sid" --argjson r "$2" --arg ev "$ev" \
    '{session_id: $sid, hook_event_name: $ev, tool_name: "Bash", tool_input: {command: $c}, tool_response: $r}'
}
record() { run_hook "$RECORDER" "$(bash_result_json "$@")"; [ "$status" -eq 0 ]; }

@test "denies a production source edit with no test run recorded (exit 2)" {
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"TDD gate"* ]]
}

@test "denies Write and MultiEdit the same way, including new directories" {
  run_hook "$GATE" "$(edit_json "$REPO/src/new/deep/app.go" s1 Write)"
  [ "$status" -eq 2 ]
  run_hook "$GATE" "$(edit_json "$REPO/src/app.ts" s1 MultiEdit)"
  [ "$status" -eq 2 ]
}

@test "subagent edits (agent_id present) are gated too" {
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py" | jq '. + {agent_id: "sub-1"}')"
  [ "$status" -eq 2 ]
}

@test "test, config and docs paths are exempt" {
  for f in tests/test_app.py src/app_test.go src/app.test.ts src/app.spec.js src/AppTest.kt \
           tests/conftest.py docs/guide.md README.md config.yaml package.json src/settings.toml \
           .harness/sdd/x/tasks.md tests/helper.py; do
    run_hook "$GATE" "$(edit_json "$REPO/$f")"
    [ "$status" -eq 0 ]
  done
}

@test "edits outside a git repo (scratchpads) are allowed" {
  OUTSIDE="$(mktemp -d)"
  run_hook "$GATE" "$(edit_json "$OUTSIDE/scratch.py")"
  [ "$status" -eq 0 ]
}

@test "a passing test run is not enough: still denied" {
  record "pytest -q" '{"stdout":"1 passed","stderr":"","interrupted":false}'
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 2 ]
}

@test "allowed after a failing test run recorded from a PostToolUseFailure event" {
  record "cd $REPO && pytest tests/test_app.py" '{}' PostToolUseFailure
  jq -n --arg sid s1 '{session_id: $sid, hook_event_name: "PostToolUseFailure", tool_name: "Bash", tool_input: {command: "go test ./..."}, error: "Exit code 1\nFAIL"}' \
    | "$RECORDER"
  tail -n 1 "$REPO/.harness/state/s1.jsonl" | jq -e '.exit == 1 and (.cmd | test("go test"))'
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 0 ]
}

@test "recorder parses the real failure payload wording and honours is_interrupt" {
  jq -n '{session_id: "s1", hook_event_name: "PostToolUseFailure", tool_name: "Bash", tool_input: {command: "pytest"}, error: "Command exited with non-zero status code 4", is_interrupt: false}' | "$RECORDER"
  jq -n '{session_id: "s1", hook_event_name: "PostToolUseFailure", tool_name: "Bash", tool_input: {command: "pytest"}, error: "aborted", is_interrupt: true}' | "$RECORDER"
  [ "$(wc -l < "$REPO/.harness/state/s1.jsonl" | tr -d ' ')" = "1" ]
  jq -e '.exit == 4' "$REPO/.harness/state/s1.jsonl"
}

@test "allowed after a failing exit_code in tool_response" {
  record "npm test" '{"stdout":"","stderr":"boom","exit_code":1}'
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 0 ]
}

@test "command-not-found (127) and interrupted runs are not a RED" {
  record "pytest" '{"exit_code":127}'
  record "pytest" '{"interrupted":true}' PostToolUseFailure
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 2 ]
}

@test "evidence is per session" {
  record "pytest" '{"exit_code":1}' s-one
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py" s-one)"
  [ "$status" -eq 0 ]
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py" s-two)"
  [ "$status" -eq 2 ]
}

@test "recorder ignores non-test commands and stores the state under .harness/state" {
  record "ls -la" '{"exit_code":1}'
  [ ! -e "$REPO/.harness/state/s1.jsonl" ]
  record "make test" '{"exit_code":2}'
  [ "$(wc -l < "$REPO/.harness/state/s1.jsonl" | tr -d ' ')" = "1" ]
  [ -f "$REPO/.harness/state/.gitignore" ]
}

@test "fails closed: bad JSON, missing file_path, missing session_id, missing jq" {
  run_hook "$GATE" "not json"; [ "$status" -eq 2 ]
  run_hook "$GATE" '{"session_id":"s1","tool_input":{}}'; [ "$status" -eq 2 ]
  run_hook "$GATE" "$(jq -n --arg fp "$REPO/src/app.py" '{tool_input: {file_path: $fp}}')"; [ "$status" -eq 2 ]
  FAKE="$(tool_path jq)"
  run_hook_with_path "$FAKE" "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 2 ]
}
