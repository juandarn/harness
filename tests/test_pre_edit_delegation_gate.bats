#!/usr/bin/env bats

setup() {
  HOOK="$BATS_TEST_DIRNAME/../plugin/claude-code/scripts/pre-edit-delegation-gate.sh"
  REPO="$(mktemp -d)"
  git -C "$REPO" init -q
  FILE="$REPO/main.py"
  echo "x = 1" > "$FILE"
}

teardown() {
  rm -rf "$REPO"
}

@test "allows subagent calls (agent_id present)" {
  INPUT="$(jq -n --arg fp "$FILE" '{agent_id: "sub-123", tool_input: {file_path: $fp}}')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "denies main session edits with the exact deny JSON" {
  INPUT="$(jq -n --arg fp "$FILE" '{tool_input: {file_path: $fp}}')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  EXPECTED='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"harness: the main session does not edit code — delegate to a subagent (code work → Sonnet; mechanical edits → Haiku). This repo enforces orchestrator-only mode."}}'
  [ "$(echo "$output" | jq -c .)" = "$(echo "$EXPECTED" | jq -c .)" ]
}

@test "allows edits outside a git repo (scratchpad)" {
  NONGIT="$(mktemp -d)"
  NG_FILE="$NONGIT/scratch.py"
  echo "x = 1" > "$NG_FILE"
  INPUT="$(jq -n --arg fp "$NG_FILE" '{tool_input: {file_path: $fp}}')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$NONGIT"
}

@test "allows edits when .harness-inline-ok opt-out is present" {
  touch "$REPO/.harness-inline-ok"
  INPUT="$(jq -n --arg fp "$FILE" '{tool_input: {file_path: $fp}}')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails open on malformed stdin" {
  run bash -c "printf 'not json' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails open when tool_input.file_path is missing" {
  run bash -c "printf '%s' '{}' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
