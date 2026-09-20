#!/usr/bin/env bats

load helpers

PLUGIN="$BATS_TEST_DIRNAME/../plugin/claude-code"
HOOKS="$PLUGIN/hooks/hooks.json"

@test "hooks.json is valid JSON and every command points at an executable script" {
  jq -e . "$HOOKS" >/dev/null
  while IFS= read -r cmd; do
    path="${cmd//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN}"
    [ -x "$path" ] || { echo "not executable: $cmd"; return 1; }
  done < <(jq -r '.hooks[][].hooks[].command' "$HOOKS")
}

@test "every hook has a timeout" {
  [ "$(jq '[.hooks[][].hooks[] | select(.timeout == null)] | length' "$HOOKS")" = "0" ]
}

@test "Bash and the three GitHub MCP writes are wired to the commit gate" {
  jq -e '[.hooks.PreToolUse[] | select(.hooks[].command | endswith("pre-commit-gate.sh")) | .matcher] | any(. == "Bash")' "$HOOKS"
  jq -e '[.hooks.PreToolUse[] | select(.hooks[].command | endswith("pre-commit-gate.sh")) | .matcher] | any(test("push_files") and test("create_or_update_file") and test("merge_pull_request"))' "$HOOKS"
}

@test "edit gates cover Edit, Write and MultiEdit: delegation, TDD order and SDD artifacts" {
  for script in pre-edit-delegation-gate.sh pre-edit-tdd-gate.sh pre-edit-sdd-gate.sh; do
    jq -e --arg s "$script" '[.hooks.PreToolUse[] | select(.hooks[].command | endswith($s)) | .matcher] | any(test("Edit") and test("Write") and test("MultiEdit"))' "$HOOKS"
  done
}

@test "read gate, test recorder (success and failure events), comment nag and Stop are wired" {
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Read") | .hooks[].command] | any(endswith("pre-read-range-gate.sh"))' "$HOOKS"
  jq -e '[.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[].command] | any(endswith("post-bash-test-recorder.sh"))' "$HOOKS"
  jq -e '[.hooks.PostToolUseFailure[] | select(.matcher == "Bash") | .hooks[].command] | any(endswith("post-bash-test-recorder.sh"))' "$HOOKS"
  jq -e '[.hooks.PostToolUse[] | .hooks[].command] | any(endswith("post-edit-comment-nag.sh"))' "$HOOKS"
  jq -e '[.hooks.Stop[].hooks[].command] | any(endswith("stop-checklist.sh"))' "$HOOKS"
}

@test "no opt-out environment variable survives in the hook scripts" {
  ! rg -q 'HARNESS_INLINE_OK' "$PLUGIN/scripts" "$PLUGIN/hooks" "$PLUGIN/gates"
}

@test "the retired tool name appears nowhere in the plugin or the tests" {
  word="$(printf 'ke%sl' e)"
  run rg -il "$word" "$PLUGIN" "$BATS_TEST_DIRNAME" -g '!__pycache__' -g '!.pytest_cache'
  [ "$status" -eq 1 ]
}

@test "shipped scripts have valid bash syntax" {
  for f in "$PLUGIN"/scripts/*.sh "$PLUGIN"/gates/*.sh "$PLUGIN"/bin/*.sh "$PLUGIN"/adapters/py/adapter.sh; do
    bash -n "$f" || { echo "syntax error: $f"; return 1; }
  done
}
