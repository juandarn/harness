#!/usr/bin/env bats

setup() {
  GRADER="$BATS_TEST_DIRNAME/../evals/local/grade-comment-restraint.sh"
  FIXTURE="$BATS_TEST_DIRNAME/../evals/local/fixtures/comment-restraint-pass.jsonl"
  WORKDIR="$(mktemp -d)"
  git -C "$WORKDIR" init -q
  git -C "$WORKDIR" config user.email "t@t"
  git -C "$WORKDIR" config user.name "t"
  echo "x = 1" > "$WORKDIR/a.py"
  git -C "$WORKDIR" add -A
  git -C "$WORKDIR" commit -qm seed
}

teardown() {
  rm -rf "$WORKDIR"
}

@test "passes when a modified file has only short comment runs" {
  {
    echo "# short note"
    echo "y = 2"
  } >> "$WORKDIR/a.py"
  run "$GRADER" "$FIXTURE" "$WORKDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no comment-nag violations"* ]]
}

@test "fails when a modified file has a long comment block" {
  {
    for i in $(seq 1 16); do echo "x = $i"; done
    echo "# one"; echo "# two"; echo "# three"; echo "# four"
    echo "y = 1"
  } > "$WORKDIR/a.py"
  run "$GRADER" "$FIXTURE" "$WORKDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"comment-nag"* ]]
}

@test "fails when a new untracked file has a long comment block" {
  {
    for i in $(seq 1 16); do echo "x = $i"; done
    echo "# one"; echo "# two"; echo "# three"; echo "# four"
    echo "y = 1"
  } > "$WORKDIR/b.py"
  run "$GRADER" "$FIXTURE" "$WORKDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"comment-nag"* ]]
}
