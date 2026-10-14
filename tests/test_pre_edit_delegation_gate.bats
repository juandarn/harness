#!/usr/bin/env bats

setup() {
  unset HARNESS_INLINE_MODELS HARNESS_DELEGATE_TO
  HOOK="$BATS_TEST_DIRNAME/../plugin/claude-code/scripts/pre-edit-delegation-gate.sh"
  REPO="$(mktemp -d)"
  git -C "$REPO" init -q
  FILE="$REPO/main.py"
  echo "x = 1" > "$FILE"
  TRANSCRIPT="$REPO/transcript.jsonl"
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

entry() { jq -nc --arg m "$1" --argjson side "${2:-false}" '{type:"assistant",isSidechain:$side,message:{model:$m,content:[{type:"text",text:"hi"}]}}'; }
edit_input() { jq -n --arg fp "$FILE" --arg tp "${1-$TRANSCRIPT}" '{transcript_path: $tp, tool_input: {file_path: $fp}}'; }
run_gate() { run bash -c "printf '%s' '$(edit_input "${2-$TRANSCRIPT}")' | $1 \"$HOOK\""; }
decision() { echo "$output" | jq -r '.hookSpecificOutput.permissionDecision'; }

@test "HARNESS_INLINE_MODELS allows the edit when the session model matches" {
  entry claude-haiku-4-5 > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku|sonnet'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  entry claude-sonnet-5-5 > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku|sonnet'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "HARNESS_INLINE_MODELS matches case-insensitively" {
  entry claude-haiku-4-5 > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='HAIKU'"
  [ -z "$output" ]
}

@test "HARNESS_INLINE_MODELS still denies a model that does not match" {
  entry claude-opus-5-5 > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku|sonnet'"
  [ "$status" -eq 0 ]
  [ "$(decision)" = "deny" ]
}

@test "the knob unset keeps denying even when the session model is haiku" {
  entry claude-haiku-4-5 > "$TRANSCRIPT"
  run_gate "env"
  [ "$(decision)" = "deny" ]
  run_gate "HARNESS_INLINE_MODELS=''"
  [ "$(decision)" = "deny" ]
}

@test "HARNESS_INLINE_MODELS denies without a transcript_path, with a missing file or without a model" {
  run bash -c "jq -n --arg fp '$FILE' '{tool_input: {file_path: \$fp}}' | HARNESS_INLINE_MODELS='haiku' \"$HOOK\""
  [ "$(decision)" = "deny" ]
  run_gate "HARNESS_INLINE_MODELS='haiku'" "$REPO/nope.jsonl"
  [ "$(decision)" = "deny" ]
  printf '{"type":"user","message":{"content":"hi"}}\nnot json\n' > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku'"
  [ "$(decision)" = "deny" ]
}

@test "a later sidechain entry does not change the main session model" {
  { entry claude-opus-5-5; entry claude-haiku-4-5 true; } > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku'"
  [ "$(decision)" = "deny" ]
  { entry claude-haiku-4-5; entry claude-opus-5-5 true; } > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku'"
  [ -z "$output" ]
}

@test "the last main entry wins over earlier ones" {
  { entry claude-haiku-4-5; entry claude-opus-5-5; } > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku'"
  [ "$(decision)" = "deny" ]
}

@test "trailing synthetic entries and non-assistant lines are skipped" {
  { entry claude-haiku-4-5; entry '<synthetic>'; echo '{"type":"user","message":{"content":"hi"}}'; } > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku'"
  [ -z "$output" ]
  { entry claude-opus-5-5; entry '<synthetic>'; } > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku'"
  [ "$(decision)" = "deny" ]
  entry '<synthetic>' > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='.'"
  [ "$(decision)" = "deny" ]
}

@test "only the last 2000 transcript lines are scanned" {
  { entry claude-haiku-4-5; for _ in $(seq 1 2500); do echo '{"type":"user"}'; done; } > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku'"
  [ "$(decision)" = "deny" ]
  { entry claude-haiku-4-5; for _ in $(seq 1 1500); do echo '{"type":"user"}'; done; } > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='haiku'"
  [ -z "$output" ]
}

@test "an invalid HARNESS_INLINE_MODELS regex fails closed" {
  entry claude-haiku-4-5 > "$TRANSCRIPT"
  run_gate "HARNESS_INLINE_MODELS='('"
  [ "$(decision)" = "deny" ]
}

@test "HARNESS_DELEGATE_TO customizes the deny reason" {
  run_gate "HARNESS_DELEGATE_TO='Sonnet via the Agent tool with model: \"sonnet\"'"
  [ "$(decision)" = "deny" ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" = 'harness: the main session does not edit code — delegate to Sonnet via the Agent tool with model: "sonnet". This repo enforces orchestrator-only mode.' ]
}

@test "an empty HARNESS_DELEGATE_TO falls back to the default reason" {
  run_gate "HARNESS_DELEGATE_TO=''"
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" = "harness: the main session does not edit code — delegate to a subagent (Sonnet). This repo enforces orchestrator-only mode." ]
}
