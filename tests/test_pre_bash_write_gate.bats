#!/usr/bin/env bats

load helpers

setup() {
  HOOK="$SCRIPTS/pre-bash-write-gate.sh"
}

bash_input() { jq -n --arg c "$1" '{tool_input: {command: $c}}'; }

assert_denied() {
  run_hook "$HOOK" "$(bash_input "$1")"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .hookSpecificOutput.permissionDecision)" = "deny" ]
  echo "$output" | jq -r .hookSpecificOutput.permissionDecisionReason | grep -q "Edit or Write"
}

assert_allowed() {
  run_hook "$HOOK" "$(bash_input "$1")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "denies python -c that opens a file for writing" {
  assert_denied "python3 -c \"open('a.py','w').write('x')\""
}

@test "denies python -c with write_text" {
  assert_denied "python3 -c \"import pathlib; pathlib.Path('a.py').write_text('x')\""
}

@test "denies node -e and ruby -e rewriting files" {
  assert_denied "node -e \"require('fs'); shutil.move('a','b')\""
  assert_denied "ruby -e \"File.open('a','w'); os.replace('a','b')\""
}

@test "denies perl -i, sed -i and tee" {
  assert_denied "perl -pi -e 's/a/b/' -i a.go"
  assert_denied "sed -i '' 's/a/b/' a.go"
  assert_denied "echo x | tee a.go"
}

@test "allows read-only one-liners" {
  assert_allowed "python3 -c \"print(1)\""
  assert_allowed "node -e \"console.log(1)\""
}

@test "allows ordinary commands" {
  assert_allowed "git status"
  assert_allowed "bats tests/test_x.bats"
}

@test "ignores empty command input" {
  run_hook "$HOOK" '{"tool_input":{}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails closed on invalid JSON" {
  run_hook "$HOOK" 'not json'
  [ "$status" -eq 2 ]
}
