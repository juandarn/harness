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

@test "denies python from stdin or a heredoc with a write marker (multi-line)" {
  assert_denied $'python3 -I - "$HT" <<"PY"\nimport sys\np=sys.argv[1]\nopen(p,"w").write("x")\nPY'
  assert_denied $'python3 - <<EOF\nfrom pathlib import Path\nPath("a.py").write_text("x")\nEOF'
  assert_denied $'perl <<EOF\nopen(F,">a.pl")\nEOF\nsed -i s/a/b/ x'
}

@test "allows a read-only python heredoc" {
  assert_allowed $'python3 - <<"PY"\nprint(1)\nPY'
}

@test "denies shell redirects into source files" {
  assert_denied $'cat >> $T <<"EOF"\nx\nEOF'
  assert_denied 'cat >> foo_test.go <<"EOF"'
  assert_denied 'echo x > src/app.py'
  assert_denied 'echo x >> web/a.tsx'
  assert_denied 'printf x >a.sh'
  assert_denied 'cat > tests/x.bats <<EOF'
}

@test "allows harmless redirects" {
  assert_allowed 'go test ./... > /dev/null 2>&1'
  assert_allowed 'cmd 2>/dev/null'
  assert_allowed 'echo x > /tmp/x.txt'
  assert_allowed 'echo x > /tmp/scratch/a.go'
  assert_allowed 'echo x >> /private/tmp/claude/a.py'
  assert_allowed 'cat >> /tmp/a.go <<"EOF"'
}

@test "main session deny message says to delegate to a Sonnet subagent" {
  run_hook "$HOOK" "$(jq -n '{tool_input:{command:"echo x > a.go"}}')"
  reason="$(echo "$output" | jq -r .hookSpecificOutput.permissionDecisionReason)"
  [[ "$reason" == *"Delegate to a Sonnet subagent"* ]]
  [[ "$reason" == *"Sonnet subagent"* ]]
  [[ "$reason" == *"FAIL"* ]]
}

@test "subagent deny message says to use Edit/Write with test first" {
  run_hook "$HOOK" "$(jq -n '{agent_id:"sub-1",tool_input:{command:"echo x > a.go"}}')"
  reason="$(echo "$output" | jq -r .hookSpecificOutput.permissionDecisionReason)"
  [[ "$reason" == *"Edit or Write"* ]]
  [[ "$reason" == *"test"* ]]
  [[ "$reason" != *"Sonnet"* ]]
}
