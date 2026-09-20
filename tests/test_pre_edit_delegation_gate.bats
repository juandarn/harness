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
  EXPECTED='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"harness: the main session does not edit code — delegate to a subagent (Sonnet). This repo enforces orchestrator-only mode."}}'
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

@test "the HARNESS_INLINE_OK env var is not an opt-out (only the per-repo file is)" {
  INPUT="$(jq -n --arg fp "$FILE" '{tool_input: {file_path: $fp}}')"
  run bash -c "printf '%s' '$INPUT' | HARNESS_INLINE_OK=1 \"$HOOK\""
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
}

@test "fails closed on malformed stdin" {
  run bash -c "printf 'not json' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
}

@test "denies when JSON is valid but tool_input.file_path is missing" {
  run bash -c "printf '%s' '{}' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
}

# Defensive: parent_tool_use_id/tool_use_id alone must never substitute for
# agent_id — see evals/local/results/20260823T045134Z (README "Live proof").
@test "denies an Edit carrying parent_tool_use_id/tool_use_id but no agent_id" {
  INPUT="$(jq -n --arg fp "$FILE" '{
    session_id: "0eb0c9e5-344e-4ccc-bd85-c2e77ea99de7",
    parent_tool_use_id: "toolu_01Az1kczxBd3N2TJbQkqgSH4",
    tool_use_id: "toolu_01GUUq82KJqoixBb2pWdMXkb",
    tool_name: "Edit",
    tool_input: {file_path: $fp, old_string: "x", new_string: "y", replace_all: false}
  }')"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
}
