#!/usr/bin/env bats

load helpers

setup() {
  HOOK="$SCRIPTS/pre-commit-gate.sh"
  new_repo
  echo '{"gates":[{"name":"ok","run":"true","severity":"block"}]}' > "$REPO/harness.gates.json"
}

teardown() {
  rm -rf "$REPO" "${FAKE:-}"
}

bash_json() { jq -n --arg c "$1" --arg cwd "${2:-$REPO}" '{tool_name: "Bash", cwd: $cwd, tool_input: {command: $c}}'; }
mcp_json() { jq -n --arg t "$1" --argjson i "$2" --arg cwd "$REPO" '{tool_name: $t, cwd: $cwd, tool_input: $i}'; }
red_gates() { echo '{"gates":[{"name":"boom","run":"echo kaput; false","severity":"block"}]}' > "$REPO/harness.gates.json"; }

@test "ignores commands that are not git commit or push" {
  for c in "ls -la" "git status" "git log --oneline" "git commit-tree HEAD^{tree}" "echo 'git commit is documented here'"; do
    run_hook "$HOOK" "$(bash_json "$c")"
    [ "$status" -eq 0 ]
  done
}

@test "allows a clean commit when gates are green and logs under .harness/logs" {
  run_hook "$HOOK" "$(bash_json 'git commit -m "feat: add thing"')"
  [ "$status" -eq 0 ]
  [ -s "$REPO/.harness/logs/pre-commit-gate.log" ]
  rg -q 'green' "$REPO/.harness/logs/pre-commit-gate.log"
}

@test "denies a Co-Authored-By trailer (exit 2)" {
  run_hook "$HOOK" "$(bash_json 'git commit -m "feat: x

Co-Authored-By: Someone <a@b.c>"')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Co-Authored-By"* || "$output" == *"co-authored-by"* ]]
}

@test "denies a heredoc message with an AI attribution line" {
  run_hook "$HOOK" "$(bash_json 'git commit -m "$(cat <<'"'"'EOF'"'"'
feat: x

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"AI attribution"* ]]
}

@test "denies a message file (-F) carrying a trailer" {
  printf 'feat: x\n\nCo-authored-by: Bot <noreply@anthropic.com>\n' > "$REPO/msg.txt"
  run_hook "$HOOK" "$(bash_json "git commit -F $REPO/msg.txt")"
  [ "$status" -eq 2 ]
}

@test "denies --no-verify on commit and push, and core.hooksPath overrides" {
  for c in 'git commit --no-verify -m "x"' 'git push --no-verify origin main' 'git -c core.hooksPath=/dev/null commit -m x'; do
    run_hook "$HOOK" "$(bash_json "$c")"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--no-verify"* ]]
  done
}

@test "denies when the repo gates are red and shows the gate output" {
  red_gates
  run_hook "$HOOK" "$(bash_json 'git commit -m "feat: x"')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"boom"* ]]
  rg -q 'RED' "$REPO/.harness/logs/pre-commit-gate.log"
}

@test "matches chained, subshell and git -C forms" {
  red_gates
  for c in 'echo hi && git commit -m x' 'true; git push origin main' '(git commit -m x)' "git -C $REPO commit -m x" 'sudo git push'; do
    run_hook "$HOOK" "$(bash_json "$c")"
    [ "$status" -eq 2 ]
  done
}

@test "follows a leading cd into another repo" {
  red_gates
  run_hook "$HOOK" "$(bash_json "cd $REPO && git commit -m x" "$(mktemp -d)")"
  [ "$status" -eq 2 ]
}

@test "falls back to gates/default.gates.json when the repo has no harness.gates.json" {
  rm "$REPO/harness.gates.json"
  run_hook "$HOOK" "$(bash_json 'git commit -m x')"
  [ "$status" -eq 0 ]
  mkdir "$REPO/tests"
  printf '#!/usr/bin/env bats\n@test "red" { false; }\n' > "$REPO/tests/t.bats"
  run_hook "$HOOK" "$(bash_json 'git commit -m x')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tests"* ]]
}

@test "push also scans the messages of unpushed commits" {
  git_commit -m "feat: sneaky" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
  run_hook "$HOOK" "$(bash_json 'git push origin main')"
  [ "$status" -eq 2 ]
}

@test "GitHub MCP writes are gated: attribution in the message is denied" {
  for t in push_files create_or_update_file; do
    run_hook "$HOOK" "$(mcp_json "mcp__plugin_yuno_github__$t" '{"message":"feat: x\n\nCo-Authored-By: A <a@b.c>","files":[]}')"
    [ "$status" -eq 2 ]
  done
  run_hook "$HOOK" "$(mcp_json mcp__plugin_yuno_github__merge_pull_request '{"commit_message":"Generated with Claude Code"}')"
  [ "$status" -eq 2 ]
}

@test "GitHub MCP writes are gated: red gates deny, clean green allows" {
  run_hook "$HOOK" "$(mcp_json mcp__plugin_yuno_github__push_files '{"message":"feat: x"}')"
  [ "$status" -eq 0 ]
  red_gates
  run_hook "$HOOK" "$(mcp_json mcp__plugin_yuno_github__push_files '{"message":"feat: x"}')"
  [ "$status" -eq 2 ]
}

@test "fails closed on invalid JSON" {
  run_hook "$HOOK" "not json"
  [ "$status" -eq 2 ]
}

@test "fails closed without jq: commit/push and MCP writes denied, other commands allowed" {
  FAKE="$(tool_path jq)"
  run_hook_with_path "$FAKE" "$HOOK" "$(bash_json 'git commit -m x')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"jq"* ]]
  run_hook_with_path "$FAKE" "$HOOK" '{"tool_name":"mcp__plugin_yuno_github__push_files","tool_input":{}}'
  [ "$status" -eq 2 ]
  run_hook_with_path "$FAKE" "$HOOK" "$(bash_json 'ls -la')"
  [ "$status" -eq 0 ]
}

@test "fails closed without python3 when a gate run is needed" {
  FAKE="$(tool_path python3)"
  run_hook_with_path "$FAKE" "$HOOK" "$(bash_json 'git commit -m x')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"python3"* ]]
}

@test "works under the macOS system bash 3.2" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  red_gates
  run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$(bash_json 'git commit -m x')" "$HOOK"
  [ "$status" -eq 2 ]
  rm "$REPO/harness.gates.json"; echo '{"gates":[]}' > "$REPO/harness.gates.json"
  run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$(bash_json 'git commit -m x')" "$HOOK"
  [ "$status" -eq 0 ]
}
