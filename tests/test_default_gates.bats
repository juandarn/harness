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

@test "comment gate: a pre-existing long comment block untouched by the change passes; touching that block blocks; adding a new long block elsewhere blocks" {
  printf '# one\n# two\n# three\n# four\n# five\nx = 1\ny = 2\n' > big.py
  git add big.py
  git_commit -m init

  echo 'z = 3' >> big.py
  run bash "$GATES/default-comments.sh"
  [ "$status" -eq 0 ]

  git -C "$REPO" checkout -- big.py
  sed -i.bak 's/# three/# THREE/' big.py && rm -f big.py.bak
  run bash "$GATES/default-comments.sh"
  [ "$status" -eq 1 ]

  git -C "$REPO" checkout -- big.py
  printf '# a\n# b\n# c\n# d\nw = 1\n' >> big.py
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
  echo 'x = 1' > a.py
  git add a.py
  FAKE="$(tool_path ruff)"
  run env -i HOME="$HOME" PATH="$FAKE" bash "$GATES/default-quality.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GATE BROKEN"* && "$output" == *"ruff"* ]]
}

@test "quality gate: a python repo with no staged .py files has nothing to run" {
  echo '[project]' > pyproject.toml
  FAKE="$(tool_path ruff)"
  run env -i HOME="$HOME" PATH="$FAKE" bash "$GATES/default-quality.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to run"* ]]
}

need_ruff() { command -v ruff >/dev/null || skip "ruff not installed"; }
ADAPTER="$BATS_TEST_DIRNAME/../plugin/claude-code/adapters/py/adapter.sh"

py_base() {
  printf 'import os\n\n\ndef f(a):\n    return a\n' > base.py
  printf 'import sys\nx  =  1\n' > debt.py
  git add base.py debt.py
  git_commit -m init
}

@test "scoped quality: unformatted and lint-dirty files that are not staged pass" {
  need_ruff
  py_base
  printf 'def g(a):\n    return a\n' > new.py
  git add new.py
  run bash "$ADAPTER" format new.py
  [ "$status" -eq 0 ]
  run bash "$ADAPTER" lint new.py
  [ "$status" -eq 0 ]
}

@test "scoped quality: a new format or lint violation on a changed line blocks" {
  need_ruff
  py_base
  printf 'def g( a ):\n    return a\n' > new.py
  git add new.py
  run bash "$ADAPTER" format new.py
  [ "$status" -eq 1 ]
  printf 'import json\n' > lint.py
  git add lint.py
  run bash "$ADAPTER" lint lint.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"F401"* ]]
}

@test "scoped quality: a pre-existing violation on an unchanged line of a touched file passes" {
  need_ruff
  py_base
  printf 'import sys\nx  =  1\n\n\ndef g(a):\n    return a\n' > debt.py
  git add debt.py
  git_commit -m debt
  printf '\n\ndef h(a):\n    return a\n' >> debt.py
  git add debt.py
  run bash "$ADAPTER" format debt.py
  [ "$status" -eq 0 ]
  run bash "$ADAPTER" lint debt.py
  [ "$status" -eq 0 ]
}

@test "scoped duplication: repeated single lines pass; a copied 4+ line block in the change blocks" {
  for i in 1 2 3 4 5 6; do printf 'def f%s(a):\n    return (\n        a + %s\n    )\n' "$i" "$i"; done > dupe.py
  git add dupe.py
  git_commit -m init
  printf 'def g(a):\n    return (\n        a * 2\n    )\n' >> dupe.py
  git add dupe.py
  run bash "$ADAPTER" duplication dupe.py
  [ "$status" -eq 0 ]
  printf 'def h(a):\n    x = a + 1\n    y = x * 2\n    z = y - 3\n    return z\n' > one.py
  git add one.py
  git_commit -m two
  printf 'def k(a):\n    x = a + 1\n    y = x * 2\n    z = y - 3\n    return z\n' >> one.py
  git add one.py
  run bash "$ADAPTER" duplication one.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRY gate"* ]]
}

@test "scoped security: an edited inner line of an old multiline SQL f-string passes; a new finding on a changed line blocks" {
  command -v bandit >/dev/null || skip "bandit not installed"
  printf 'def q(t):\n    return (\n        f"SELECT a "\n        f"FROM {t} "\n        f"WHERE x = 1"\n    )\n' > sql.py
  git add sql.py
  git_commit -m init
  sed -i.bak 's/x = 1/x = 2/' sql.py && rm -f sql.py.bak
  git add sql.py
  run bash "$ADAPTER" security sql.py
  [ "$status" -eq 0 ]
  printf '\n\ndef r(t):\n    return f"SELECT b FROM {t}"\n' >> sql.py
  git add sql.py
  run bash "$ADAPTER" security sql.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"B608"* ]]
}

fake_py() {
  mkdir -p "$1/bin"
  printf '#!/usr/bin/env bash\n[ "$1" = -c ] && exit 0\necho "%s $*"\n' "$2" > "$1/bin/python"
  chmod +x "$1/bin/python"
}

py_tests_repo() {
  echo '[project]' > pyproject.toml
  printf 'def f(): pass\n' > mod.py
  printf 'def g(): pass\n' > other.py
  printf 'import mod\n' > test_mod.py
  printf 'import other\n' > test_other.py
  git add -A
  git_commit -m init
  fake_py .venv FAKE
}

@test "python tests gate: only tests that reference a staged module run" {
  py_tests_repo
  echo '# touch' >> mod.py
  git add mod.py
  run bash "$GATES/default-tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test_mod.py"* ]]
  [[ "$output" != *"test_other.py"* ]]
}

@test "python tests gate: nothing affected passes without running pytest" {
  py_tests_repo
  echo doc > README.md
  git add README.md
  run bash "$GATES/default-tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no affected tests"* ]]
  [[ "$output" != *"FAKE"* ]]
}

@test "python tests gate: a staged conftest.py runs the full suite" {
  py_tests_repo
  echo '# c' > conftest.py
  git add conftest.py
  run bash "$GATES/default-tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FAKE -m pytest -q"* ]]
  [[ "$output" != *"test_mod.py"* ]]
}

@test "python tests gate: ./.venv python wins over ./venv" {
  py_tests_repo
  fake_py venv VENV
  echo '# touch' >> mod.py
  git add mod.py
  run bash "$GATES/default-tests.sh"
  [[ "$output" == *"FAKE -m pytest"* ]]
  rm -rf .venv
  run bash "$GATES/default-tests.sh"
  [[ "$output" == *"VENV -m pytest"* ]]
}

@test "python tests gate: GATE_DIFF_ARGS selects the change" {
  py_tests_repo
  echo '# touch' >> mod.py
  git add mod.py
  git_commit -m touch
  run env GATE_DIFF_ARGS="HEAD~1 HEAD" bash "$GATES/default-tests.sh"
  [[ "$output" == *"test_mod.py"* ]]
}

@test "lib.sh reads the pinned thresholds from harness.toolchain.yaml" {
  run bash -c 'source "$1/lib.sh"; threshold coverage_min' _ "$GATES"
  [ "$status" -eq 0 ]
  [ "$output" = "80" ]
}

start_merge() {
  printf 'x = 1\n' > a.py
  git -C "$REPO" add a.py
  git_commit -m init
  git -C "$REPO" branch -M main
  git -C "$REPO" checkout -q -b feat
  printf 'y = 1\n' > ours.py
  git -C "$REPO" add ours.py
  git_commit -m ours
  git -C "$REPO" checkout -q main
  printf '# 1\n# 2\n# 3\n# 4\n# 5\n# 6\nz = 1\n' > theirs.py
  git -C "$REPO" add theirs.py
  git_commit -m theirs
  git -C "$REPO" checkout -q feat
  git -C "$REPO" -c user.name=t -c user.email=t@t merge --no-commit --no-ff main >/dev/null
}

@test "comment gate: mid-merge, a comment block that only came from the merged side passes" {
  start_merge
  run bash "$GATES/default-comments.sh"
  [ "$status" -eq 0 ]
}

@test "comment gate: mid-merge, our own long comment block still blocks" {
  start_merge
  printf '# a\n# b\n# c\n# d\n# e\n# f\n' >> ours.py
  run bash "$GATES/default-comments.sh"
  [ "$status" -eq 1 ]
}

@test "comment gate: generated files are skipped" {
  git_commit -m init
  printf '// Code generated by sqlc. DO NOT EDIT.\n// 1\n// 2\n// 3\n// 4\n// 5\npackage db\n' > gen.go
  run bash "$GATES/default-comments.sh"
  [ "$status" -eq 0 ]
}

@test "comment gate: outside a merge a long block from a plain commit-less change still blocks" {
  git_commit -m init
  printf '// a\n// b\n// c\n// d\n// e\n// f\npackage db\n' > hand.go
  run bash "$GATES/default-comments.sh"
  [ "$status" -eq 1 ]
}
