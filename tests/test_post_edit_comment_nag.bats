#!/usr/bin/env bats

setup() {
  HOOK="$BATS_TEST_DIRNAME/../plugin/claude-code/scripts/post-edit-comment-nag.sh"
  FILE="$(mktemp /tmp/post-edit-nag-test.XXXXXX.py)"
}

teardown() {
  rm -f "$FILE"
}

@test "emits a block decision when the gate fails" {
  {
    for i in $(seq 1 16); do echo "x = $i"; done
    echo "# one"; echo "# two"; echo "# three"; echo "# four"
  } > "$FILE"
  INPUT="{\"tool_input\":{\"file_path\":\"$FILE\"}}"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision"'* ]]
  [[ "$output" == *'"block"'* ]]
}

@test "produces no output for a clean file" {
  echo "x = 1" > "$FILE"
  INPUT="{\"tool_input\":{\"file_path\":\"$FILE\"}}"
  run bash -c "printf '%s' '$INPUT' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 silently when file_path is missing" {
  run bash -c "printf '%s' '{}' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
