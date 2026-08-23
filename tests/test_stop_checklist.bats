#!/usr/bin/env bats

setup() {
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

@test "silent when stop_hook_active is true (loop protection)" {
  INPUT="$(jq -n --arg cwd "$PROJECT" '{cwd: $cwd, stop_hook_active: true}')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
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
