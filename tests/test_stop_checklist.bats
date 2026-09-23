#!/usr/bin/env bats

setup() {
  unset CLAUDE_PROJECT_DIR
  HOOK="$BATS_TEST_DIRNAME/../plugin/claude-code/scripts/stop-checklist.sh"
  PROJECT="$(mktemp -d)"
}

teardown() {
  rm -rf "$PROJECT"
}

@test "silent when no harness.gates.json exists" {
  INPUT="$(jq -n --arg cwd "$PROJECT" '{cwd: $cwd}')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no gate runs when the repo has no harness.gates.json, even with a red test suite present" {
  mkdir "$PROJECT/tests"
  printf '#!/usr/bin/env bats\n@test "red" { false; }\n' > "$PROJECT/tests/t.bats"
  INPUT="$(jq -n --arg cwd "$PROJECT" '{cwd: $cwd, session_id: "s-default-red"}')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stop_hook_active no longer short-circuits the gates" {
  jq -n '{gates: [{name: "boom", run: "false", severity: "block"}]}' > "$PROJECT/harness.gates.json"
  INPUT="$(jq -n --arg cwd "$PROJECT" '{cwd: $cwd, session_id: "s-active", stop_hook_active: true}')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
}

@test "blocks at most 3 times per session, then releases" {
  jq -n '{gates: [{name: "boom", run: "false", severity: "block"}]}' > "$PROJECT/harness.gates.json"
  INPUT="$(jq -n --arg cwd "$PROJECT" '{cwd: $cwd, session_id: "s-cap"}')"
  for i in 1 2 3; do
    run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  done
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [[ "$output" != *'"block"'* ]]
  [ "$(cat "$PROJECT/.harness/state/s-cap.stop-blocks")" = "3" ]
}

@test "the block counter is per session" {
  jq -n '{gates: [{name: "boom", run: "false", severity: "block"}]}' > "$PROJECT/harness.gates.json"
  for sid in a b; do
    INPUT="$(jq -n --arg cwd "$PROJECT" --arg sid "$sid" '{cwd: $cwd, session_id: $sid}')"
    run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
    [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  done
}

@test "silent when all gates pass" {
  jq -n '{gates: [{name: "ok", run: "true", severity: "block"}]}' > "$PROJECT/harness.gates.json"
  INPUT="$(jq -n --arg cwd "$PROJECT" '{cwd: $cwd}')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "emits a block decision with a reason when a blocking gate fails" {
  jq -n '{gates: [{name: "boom", run: "false", severity: "block"}]}' > "$PROJECT/harness.gates.json"
  INPUT="$(jq -n --arg cwd "$PROJECT" '{cwd: $cwd}')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  [[ "$(echo "$output" | jq -r '.reason')" == *"harness gates failed"* ]]
}
