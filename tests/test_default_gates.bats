#!/usr/bin/env bats

load helpers

setup() {
  new_repo
  cd "$REPO"
}

teardown() {
  cd /
  rm -rf "$REPO" "${FAKE:-}"
}

@test "default.gates.json defines blocking tests, comment-restraint and quality gates" {
  for n in tests comment-restraint quality; do
    jq -e --arg n "$n" '.gates[] | select(.name == $n and .severity == "block")' "$GATES/default.gates.json"
  done
}

@test "run_gates.py resolves HARNESS_ROOT for the default gates in an empty repo" {
  run python3 "$GATES/run_gates.py" "$GATES/default.gates.json" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all green"* ]]
}

@test "tests gate: nothing detected means nothing to run" {
  run bash "$GATES/default-tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no test runner detected"* ]]
}

@test "tests gate: a red bats suite blocks and a green one passes" {
  mkdir tests
  printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > tests/a.bats
  run bash "$GATES/default-tests.sh"
  [ "$status" -eq 0 ]
  printf '#!/usr/bin/env bats\n@test "bad" { false; }\n' > tests/b.bats
  run bash "$GATES/default-tests.sh"
  [ "$status" -eq 1 ]
}

@test "tests gate: a detected runner with its tool missing blocks instead of skipping" {
  echo 'module x' > go.mod
  FAKE="$(tool_path go)"
  run env -i HOME="$HOME" PATH="$FAKE" bash "$GATES/default-tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GATE BROKEN"* ]]
}

@test "tests gate: package.json without a real test script is ignored" {
  echo '{"scripts":{"test":"echo \"Error: no test specified\" && exit 1"}}' > package.json
  run bash "$GATES/default-tests.sh"
  [ "$status" -eq 0 ]
}

@test "comment gate: nothing changed passes; a long comment block in a new file blocks" {
  git_commit -m init
  run bash "$GATES/default-comments.sh"
  [ "$status" -eq 0 ]
  printf '# one\n# two\n# three\n# four\n# five\nx = 1\n' > big.py
  run bash "$GATES/default-comments.sh"
  [ "$status" -eq 1 ]
}

@test "comment gate: outside a git repo there is nothing to compare" {
  OUT="$(mktemp -d)"
  cd "$OUT"
  run bash "$GATES/default-comments.sh"
  cd /
  rm -rf "$OUT"
  [ "$status" -eq 0 ]
}

@test "quality gate: a repo with no adapter says so and passes" {
  run bash "$GATES/default-quality.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no quality adapter"* ]]
}

@test "quality gate: a python repo with ruff missing fails loud" {
  echo '[project]' > pyproject.toml
  FAKE="$(tool_path ruff)"
  run env -i HOME="$HOME" PATH="$FAKE" bash "$GATES/default-quality.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GATE BROKEN"* && "$output" == *"ruff"* ]]
}

@test "lib.sh reads the pinned thresholds from harness.toolchain.yaml" {
  run bash -c 'source "$1/lib.sh"; threshold coverage_min' _ "$GATES"
  [ "$status" -eq 0 ]
  [ "$output" = "80" ]
}
