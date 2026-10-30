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

@test "no pre-edit gate is wired: Edit and Write are never blocked by a hook" {
  ! jq -e '[.hooks.PreToolUse[] | select(.matcher | test("Edit|Write"))] | length > 0' "$HOOKS"
}

@test "read gate, comment nag and Stop are wired" {
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "Read") | .hooks[].command] | any(endswith("pre-read-range-gate.sh"))' "$HOOKS"
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
