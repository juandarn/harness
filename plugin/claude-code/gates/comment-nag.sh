#!/usr/bin/env bash
# usage: comment-nag.sh <file> [changed-lines-file]
# Single rule: 1-2 line comments are fine, 4+ consecutive full-line comments fail (shebang excluded).
# With changed-lines-file, only blocks a run touched by a changed line; without it, checks the whole file.
set -euo pipefail

FILE="${1:?usage: comment-nag.sh <file> [changed-lines-file]}"
LINES_FILE="${2:-}"

[ -f "$FILE" ] || exit 0

case "$FILE" in
  *.go|*.py|*.ts|*.tsx|*.js|*.jsx|*.kt|*.kts|*.sh|*.bash|*.sql|*.rb|*.rs|*.java) ;;
  *) exit 0 ;;
esac

awk -v file="$FILE" -v lines_file="$LINES_FILE" '
BEGIN {
  scoped = (lines_file != "")
  if (scoped) {
    while ((getline ln < lines_file) > 0) touched[ln] = 1
    close(lines_file)
  }
}
function is_comment(line,    t) {
  t = line
  sub(/^[ \t]+/, "", t)
  if (t ~ /^\/\//) return 1
  if (t ~ /^#/) return 1
  if (t ~ /^--/) return 1
  if (t ~ /^\/\*.*\*\/[ \t]*$/) return 1
  return 0
}
function block_touched(start, len,    i) {
  for (i = start; i < start + len; i++) if (i in touched) return 1
  return 0
}
function flag(start, len) {
  if (len >= 4 && (!scoped || block_touched(start, len))) {
    printf "%s:%d: comment block of %d lines (max 3) — trim to 1-2 lines stating only the non-obvious constraint\n", file, start, len
    violation = 1
  }
}
{
  if (NR == 1 && $0 ~ /^#!/) next
  if (is_comment($0)) {
    if (run_len == 0) run_start = NR
    run_len++
  } else {
    if (run_len > 0) flag(run_start, run_len)
    run_len = 0
  }
}
END {
  if (run_len > 0) flag(run_start, run_len)
  exit violation ? 1 : 0
}
' "$FILE"
