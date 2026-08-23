#!/usr/bin/env bats

setup() {
  GRADER="$BATS_TEST_DIRNAME/../evals/local/grade-tdd-order.sh"
  FIXTURES="$BATS_TEST_DIRNAME/../evals/local/fixtures"
  WORKDIR="/tmp/eval-workdir"
}

@test "passes on a red-then-green cycle with test written first" {
  run "$GRADER" "$FIXTURES/tdd-order-pass.jsonl" "$WORKDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TDD proof"* ]]
}

@test "fails when source is written with no test at all" {
  run "$GRADER" "$FIXTURES/tdd-order-fail.jsonl" "$WORKDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no test was written"* ]]
}
