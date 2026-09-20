#!/usr/bin/env bats

setup() {
  GATE="$BATS_TEST_DIRNAME/../plugin/claude-code/gates/comment-nag.sh"
  FILE="$(mktemp /tmp/comment-nag-test.XXXXXX.py)"
}

teardown() {
  rm -f "$FILE"
}

@test "passes on a clean file with short comment runs" {
  cat > "$FILE" <<'EOF'
# short header
def foo():
    # explains the non-obvious bit
    return 1
EOF
  run "$GATE" "$FILE"
  [ "$status" -eq 0 ]
}

@test "flags a run of 4 consecutive comments" {
  {
    for i in $(seq 1 16); do echo "x = $i"; done
    echo "# one"
    echo "# two"
    echo "# three"
    echo "# four"
    echo "y = 1"
  } > "$FILE"
  run "$GATE" "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"comment block of 4 lines"* ]]
}

@test "flags a 4-line comment run at the top of the file (single rule, no header exemption)" {
  {
    echo "# one"
    echo "# two"
    echo "# three"
    echo "# four"
    echo "y = 1"
  } > "$FILE"
  run "$GATE" "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"comment block of 4 lines"* ]]
}

@test "allows 1-3 line comment runs" {
  printf '# one\nx = 1\n# a\n# b\ny = 2\n# a\n# b\n# c\nz = 3\n' > "$FILE"
  run "$GATE" "$FILE"
  [ "$status" -eq 0 ]
}

@test "the shebang line does not count towards a comment run" {
  SH_FILE="$(mktemp /tmp/comment-nag-test.XXXXXX.sh)"
  printf '#!/usr/bin/env bash\n# one\n# two\n# three\necho hi\n' > "$SH_FILE"
  run "$GATE" "$SH_FILE"
  [ "$status" -eq 0 ]
  rm -f "$SH_FILE"
}

@test "skips non-code files" {
  TXT="$(mktemp /tmp/comment-nag-test.XXXXXX.txt)"
  {
    for i in $(seq 1 16); do echo "line $i"; done
    echo "# one"; echo "# two"; echo "# three"; echo "# four"
  } > "$TXT"
  run "$GATE" "$TXT"
  [ "$status" -eq 0 ]
  rm -f "$TXT"
}

@test "exits 0 when file does not exist" {
  run "$GATE" "/tmp/does-not-exist-$$.py"
  [ "$status" -eq 0 ]
}

@test "flags a comment run that ends at EOF" {
  GO_FILE="$(mktemp /tmp/comment-nag-test.XXXXXX.go)"
  {
    for i in $(seq 1 16); do echo "x := $i"; done
    echo "// one"
    echo "// two"
    echo "// three"
    echo "// four"
  } > "$GO_FILE"
  run "$GATE" "$GO_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"comment block of 4 lines"* ]]
  rm -f "$GO_FILE"
}

@test "detects // and -- comment markers" {
  SQL_FILE="$(mktemp /tmp/comment-nag-test.XXXXXX.sql)"
  {
    for i in $(seq 1 16); do echo "SELECT $i;"; done
    echo "-- one"
    echo "-- two"
    echo "-- three"
    echo "-- four"
    echo "SELECT 1;"
  } > "$SQL_FILE"
  run "$GATE" "$SQL_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"comment block of 4 lines"* ]]
  rm -f "$SQL_FILE"
}
