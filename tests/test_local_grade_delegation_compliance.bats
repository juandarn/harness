#!/usr/bin/env bats

setup() {
  GRADER="$BATS_TEST_DIRNAME/../evals/local/grade-delegation-compliance.sh"
  FIXTURES="$BATS_TEST_DIRNAME/../evals/local/fixtures"
  WORKDIR="/tmp/eval-workdir"
}

@test "passes when a denied direct edit is followed by Task delegation" {
  run "$GRADER" "$FIXTURES/delegation-compliance-pass.jsonl" "$WORKDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delegated"* ]]
}

@test "fails when a direct edit on a repo file succeeds" {
  run "$GRADER" "$FIXTURES/delegation-compliance-fail.jsonl" "$WORKDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"succeeded from the main session"* ]]
}

@test "fails when no Task delegation is observed" {
  run "$GRADER" "$FIXTURES/delegation-compliance-fail-no-delegation.jsonl" "$WORKDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"was not delegated"* ]]
}

@test "passes when delegation uses the Agent (async subagent) tool" {
  run "$GRADER" "$FIXTURES/delegation-compliance-pass-agent-tool.jsonl" "$WORKDIR"
  [ "$status" -eq 0 ]
}

@test "fails on a successful edit even when workdir arg is non-canonical (/var vs /private/var)" {
  run "$GRADER" "$FIXTURES/delegation-compliance-fail-symlinked-path.jsonl" "/var/tmp/eval-workdir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"succeeded from the main session"* ]]
}
