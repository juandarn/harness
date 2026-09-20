#!/usr/bin/env bash
# usage: comment-nag.sh <file>
# Single rule: 1-2 line comments are fine, 4+ consecutive full-line comments fail (shebang excluded).
set -euo pipefail

FILE="${1:?usage: comment-nag.sh <file>}"

[ -f "$FILE" ] || exit 0

case "$FILE" in
  *.go|*.py|*.ts|*.tsx|*.js|*.jsx|*.kt|*.kts|*.sh|*.bash|*.sql|*.rb|*.rs|*.java) ;;
  *) exit 0 ;;
esac

awk -v file="$FILE" '
function is_comment(line,    t) {
  t = line
  sub(/^[ \t]+/, "", t)
  if (t ~ /^\/\//) return 1
  if (t ~ /^#/) return 1
  if (t ~ /^--/) return 1
  if (t ~ /^\/\*.*\*\/[ \t]*$/) return 1
  return 0
}
function flag(start, len) {
  if (len >= 4) {
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
