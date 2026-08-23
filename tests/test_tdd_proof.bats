#!/usr/bin/env bats

setup() {
  GATE="$BATS_TEST_DIRNAME/../plugin/claude-code/gates/tdd-proof.sh"
  TRANSCRIPT="$(mktemp)"
}

teardown() {
  rm -f "$TRANSCRIPT"
}

@test "passes when no source file was touched" {
  printf '%s\n' '{"tool":"Write","path":"README.md"}' > "$TRANSCRIPT"
  run "$GATE" "$TRANSCRIPT"
  [ "$status" -eq 0 ]
}

@test "blocks when source changed but no test exists" {
  printf '%s\n' '{"tool":"Write","path":"foo.py"}' > "$TRANSCRIPT"
  run "$GATE" "$TRANSCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no test was written"* ]]
}

@test "blocks when source is written before its test" {
  {
    echo '{"tool":"Write","path":"foo.py"}'
    echo '{"tool":"Write","path":"foo_test.py"}'
  } > "$TRANSCRIPT"
  run "$GATE" "$TRANSCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"code-first"* ]]
}

@test "blocks when no red run was observed" {
  {
    echo '{"tool":"Write","path":"foo_test.py"}'
    echo '{"tool":"Write","path":"foo.py"}'
    echo '{"tool":"Bash","cmd":"pytest","exit":0}'
  } > "$TRANSCRIPT"
  run "$GATE" "$TRANSCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RED"* ]]
}

@test "passes on full red-then-green cycle" {
  {
    echo '{"tool":"Write","path":"foo_test.py"}'
    echo '{"tool":"Bash","cmd":"pytest","exit":1}'
    echo '{"tool":"Write","path":"foo.py"}'
    echo '{"tool":"Bash","cmd":"pytest","exit":0}'
  } > "$TRANSCRIPT"
  run "$GATE" "$TRANSCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TDD proof"* ]]
}
