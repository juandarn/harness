#!/usr/bin/env bats

load helpers

SCRIPT="$SCRIPTS/subagent-statusline.sh"

@test "shows model, agent type and label on the task row" {
  run_hook "$SCRIPT" '{"columns":120,"tasks":[{"id":"t1","agentType":"general-purpose","label":"scan repo","model":"claude-sonnet-5-5"}]}'
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -r .id)" = "t1" ]
  [ "$(printf '%s\n' "$output" | jq -r .content)" = "sonnet-5-5 · general-purpose · scan repo" ]
}

@test "falls back to type and description, and appends effort" {
  run_hook "$SCRIPT" '{"columns":120,"tasks":[{"id":"t1","type":"local_agent","description":"fix bug","model":"claude-opus-5","effort":"high"}]}'
  [ "$(printf '%s\n' "$output" | jq -r .content)" = "opus-5 · local_agent · fix bug · high" ]
}

@test "task without model gets no line, others keep theirs" {
  run_hook "$SCRIPT" '{"columns":120,"tasks":[{"id":"a","agentType":"x","label":"l"},{"id":"b","agentType":"x","label":"l","model":"claude-haiku-5"}]}'
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "1" ]
  [ "$(printf '%s\n' "$output" | jq -r .id)" = "b" ]
}

@test "content is truncated to columns" {
  run_hook "$SCRIPT" '{"columns":20,"tasks":[{"id":"t1","agentType":"general-purpose","label":"a very long label indeed","model":"claude-sonnet-5-5"}]}'
  [ "$(printf '%s\n' "$output" | jq -r '.content | length')" = "20" ]
}

@test "garbage stdin exits 0 with no output" {
  run_hook "$SCRIPT" 'not json {'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "empty stdin exits 0 with no output" {
  run_hook "$SCRIPT" ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
