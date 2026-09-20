#!/usr/bin/env bats

load helpers

setup() {
  GATE="$SCRIPTS/pre-edit-sdd-gate.sh"
  new_repo
  mkdir -p "$REPO/src"
}

teardown() {
  rm -rf "$REPO" "${FAKE:-}"
}

edit_json() { jq -n --arg fp "$1" --arg tool "${2:-Edit}" '{session_id: "s1", tool_name: $tool, tool_input: {file_path: $fp}}'; }

@test "allows source edits when the repo has no .harness/sdd directory" {
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 0 ]
}

@test "allows source edits when .harness/sdd has no change directories" {
  mkdir -p "$REPO/.harness/sdd"
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 0 ]
}

@test "denies source edits while the active change has no tasks.md (exit 2)" {
  mkdir -p "$REPO/.harness/sdd/add-refunds"
  echo "# spec" > "$REPO/.harness/sdd/add-refunds/spec.md"
  for tool in Edit Write MultiEdit; do
    run_hook "$GATE" "$(edit_json "$REPO/src/app.py" $tool)"
    [ "$status" -eq 2 ]
    [[ "$output" == *"add-refunds"* && "$output" == *"tasks.md"* ]]
  done
}

@test "an empty tasks.md does not count" {
  mkdir -p "$REPO/.harness/sdd/c1"
  : > "$REPO/.harness/sdd/c1/tasks.md"
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 2 ]
}

@test "allows source edits once tasks.md exists" {
  mkdir -p "$REPO/.harness/sdd/c1"
  echo "- [ ] task" > "$REPO/.harness/sdd/c1/tasks.md"
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 0 ]
}

@test "the SDD artifacts themselves, tests and docs stay editable while blocked" {
  mkdir -p "$REPO/.harness/sdd/c1"
  for f in .harness/sdd/c1/tasks.md .harness/sdd/c1/spec.md tests/test_app.py docs/notes.md config.json; do
    run_hook "$GATE" "$(edit_json "$REPO/$f")"
    [ "$status" -eq 0 ]
  done
}

@test "archived changes are ignored and the most recent change decides" {
  mkdir -p "$REPO/.harness/sdd/archive/old" "$REPO/.harness/sdd/older" "$REPO/.harness/sdd/newer"
  touch -t 202001010000 "$REPO/.harness/sdd/older"
  echo "- [ ] t" > "$REPO/.harness/sdd/newer/tasks.md"
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 0 ]
  mkdir "$REPO/.harness/sdd/newest"
  touch -t 203001010000 "$REPO/.harness/sdd/newest"
  run_hook "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 2 ]
}

@test "fails closed on bad JSON, missing file_path and missing jq" {
  run_hook "$GATE" "not json"; [ "$status" -eq 2 ]
  run_hook "$GATE" '{"tool_input":{}}'; [ "$status" -eq 2 ]
  FAKE="$(tool_path jq)"
  run_hook_with_path "$FAKE" "$GATE" "$(edit_json "$REPO/src/app.py")"
  [ "$status" -eq 2 ]
}
