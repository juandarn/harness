#!/usr/bin/env bats

setup() {
  GATE="$BATS_TEST_DIRNAME/../plugin/claude-code/gates/artifact-gate.sh"
  WORKDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORKDIR"
}

@test "passes when required artifact exists and is non-empty" {
  echo "content" > "$WORKDIR/brief.md"
  run "$GATE" INTAKE "$WORKDIR"
  [ "$status" -eq 0 ]
}

@test "fails when required artifact is missing" {
  run "$GATE" INTAKE "$WORKDIR"
  [ "$status" -eq 1 ]
}

@test "fails when required artifact is empty" {
  touch "$WORKDIR/brief.md"
  run "$GATE" INTAKE "$WORKDIR"
  [ "$status" -eq 1 ]
}

@test "passes for phases with no required artifact" {
  run "$GATE" UNKNOWN_PHASE "$WORKDIR"
  [ "$status" -eq 0 ]
}

@test "fails with usage message when PHASE is missing" {
  run "$GATE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}
