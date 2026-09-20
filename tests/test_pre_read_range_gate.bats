#!/usr/bin/env bats

setup() {
  unset HARNESS_READ_GATE
  HOOK="$BATS_TEST_DIRNAME/../plugin/claude-code/scripts/pre-read-range-gate.sh"
  DIR="$(mktemp -d)"
  BIG="$DIR/big.py"; seq 1 500 > "$BIG"
  SMALL="$DIR/small.py"; seq 1 50 > "$SMALL"
}

teardown() {
  rm -rf "$DIR"
}

read_input() { jq -n --arg fp "$1" --argjson extra "${2:-{\}}" '{tool_input: ({file_path: $fp} + $extra)}'; }

@test "denies a whole-file read of a large file" {
  run bash -c "$(declare -f read_input); read_input '$BIG' | '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .hookSpecificOutput.permissionDecision)" = "deny" ]
  echo "$output" | jq -r .hookSpecificOutput.permissionDecisionReason | grep -q "500 lines"
}

@test "allows a large file when an explicit limit is given" {
  run bash -c "$(declare -f read_input); read_input '$BIG' '{\"offset\":100,\"limit\":50}' | '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows small files" {
  run bash -c "$(declare -f read_input); read_input '$SMALL' | '$HOOK'"
  [ -z "$output" ]
}

@test "respects HARNESS_READ_MAX_LINES" {
  run bash -c "$(declare -f read_input); read_input '$BIG' | HARNESS_READ_MAX_LINES=1000 '$HOOK'"
  [ -z "$output" ]
}

@test "is on by default and only HARNESS_READ_GATE=0 turns it off" {
  run bash -c "$(declare -f read_input); read_input '$BIG' | '$HOOK'"
  [ "$(echo "$output" | jq -r .hookSpecificOutput.permissionDecision)" = "deny" ]
  run bash -c "$(declare -f read_input); read_input '$BIG' | HARNESS_READ_GATE=0 '$HOOK'"
  [ -z "$output" ]
}

@test "skips images and missing files, fails closed on bad JSON" {
  cp "$BIG" "$DIR/x.png"
  run bash -c "$(declare -f read_input); read_input '$DIR/x.png' | '$HOOK'"; [ -z "$output" ]
  run bash -c "$(declare -f read_input); read_input '$DIR/nope.py' | '$HOOK'"; [ -z "$output" ]
  run bash -c "printf 'not json' | '$HOOK'"; [ "$status" -eq 2 ]
}
