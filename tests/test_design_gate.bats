#!/usr/bin/env bats
# Stubs npx for fast/deterministic runs; one real end-to-end case hits the
# actual detector (network-dependent, skipped if npx is unavailable).

setup() {
  GATE="$BATS_TEST_DIRNAME/../plugin/claude-code/gates/design-gate.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures/design-gate"
  STUBDIR="$(mktemp -d)"
  WORKDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$STUBDIR" "$WORKDIR"
}

# Writes a fake `npx` that returns a fixed JSON body and exit status,
# mimicking `impeccable detect --json`.
stub_npx() {
  local body="$1" status="$2"
  cat > "$STUBDIR/npx" <<EOF
#!/usr/bin/env bash
cat <<'JSON'
$body
JSON
exit $status
EOF
  chmod +x "$STUBDIR/npx"
}

@test "passes when the stubbed detector reports no findings" {
  stub_npx '[]' 0
  PATH="$STUBDIR:$PATH" run "$GATE" "$WORKDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "fails and lists file:line rule findings from the stubbed detector" {
  stub_npx '[{"file":"a.html","line":3,"antipattern":"low-contrast","snippet":"2.8:1"}]' 2
  PATH="$STUBDIR:$PATH" run "$GATE" "$WORKDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 blocking finding"* ]]
  [[ "$output" == *"a.html:3 [low-contrast] 2.8:1"* ]]
}

@test "caps output at 30 findings plus a remainder count" {
  BODY="["
  for i in $(seq 1 35); do
    [ "$i" -gt 1 ] && BODY="$BODY,"
    BODY="$BODY{\"file\":\"f.html\",\"line\":$i,\"antipattern\":\"rule\",\"snippet\":\"x\"}"
  done
  BODY="$BODY]"
  stub_npx "$BODY" 2
  PATH="$STUBDIR:$PATH" run "$GATE" "$WORKDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"35 blocking finding"* ]]
  [[ "$output" == *"... and 5 more"* ]]
}

@test "fails open with a notice when the detector output is not JSON" {
  stub_npx 'garbage, not json' 1
  PATH="$STUBDIR:$PATH" run "$GATE" "$WORKDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"impeccable not available"* ]]
}

@test "fails open with a notice when npx is not on PATH" {
  run env -i PATH=/usr/bin:/bin "$GATE" "$WORKDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"impeccable not available — install with npx impeccable install"* ]]
}

@test "fails with usage message when dir is missing" {
  run "$GATE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "real detector: blocks on the violating fixture" {
  command -v npx >/dev/null 2>&1 || skip "npx not available"
  run "$GATE" "$FIXTURES/bad"
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocking finding"* ]]
}
