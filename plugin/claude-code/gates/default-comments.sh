#!/usr/bin/env bash
# Default `comment-restraint` gate: runs comment-nag.sh over lines changed vs HEAD
# for each tracked file (whole file for untracked). Outside a git work tree there is nothing to compare.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo — nothing to check"; exit 0; }

files="$( { git diff --name-only HEAD 2>/dev/null || git diff --name-only --cached; git ls-files --others --exclude-standard; } | sort -u)"
untracked="$(git ls-files --others --exclude-standard)"

tmpfiles=()
cleanup() { [ "${#tmpfiles[@]}" -eq 0 ] || rm -f "${tmpfiles[@]}"; }
trap cleanup EXIT

# changed_lines_file <file>: writes added/modified line numbers (vs HEAD) to a temp file, prints its path.
changed_lines_file() {
  local f="$1" tmp
  tmp="$(mktemp)"
  tmpfiles+=("$tmp")
  git diff -U0 HEAD -- "$f" 2>/dev/null | while IFS= read -r hunk_line; do
    [[ "$hunk_line" == @@*@@* ]] || continue
    if [[ "$hunk_line" =~ \+([0-9]+)(,([0-9]+))? ]]; then
      local start="${BASH_REMATCH[1]}" count="${BASH_REMATCH[3]:-1}"
      [ "$count" -eq 0 ] && continue
      for ((i = 0; i < count; i++)); do echo $((start + i)); done
    fi
  done > "$tmp"
  printf '%s' "$tmp"
}

status=0
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  if grep -qxF "$f" <<<"$untracked"; then
    "$HERE/comment-nag.sh" "$f" || status=1
  else
    lf="$(changed_lines_file "$f")"
    "$HERE/comment-nag.sh" "$f" "$lf" || status=1
  fi
done <<EOF
$files
EOF

[ "$status" -eq 0 ] && echo "comment restraint ok"
exit "$status"
