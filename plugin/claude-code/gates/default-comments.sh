#!/usr/bin/env bash
# Default `comment-restraint` gate: runs comment-nag.sh over lines changed vs HEAD
# for each tracked file (whole file for untracked). Outside a git work tree there is nothing to compare.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo — nothing to check"; exit 0; }

# Mid-merge, only our own changes count: lines/files that differ from both parents.
merging=""; git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && merging=1

if [ -n "$merging" ]; then
  files="$( { comm -12 <(git diff --name-only HEAD | sort) <(git diff --name-only MERGE_HEAD | sort); git ls-files --others --exclude-standard; } | sort -u)"
else
  files="$( { git diff --name-only HEAD 2>/dev/null || git diff --name-only --cached; git ls-files --others --exclude-standard; } | sort -u)"
fi
untracked="$(git ls-files --others --exclude-standard)"

tmpfiles=()
cleanup() { [ "${#tmpfiles[@]}" -eq 0 ] || rm -f "${tmpfiles[@]}"; }
trap cleanup EXIT

# diff_lines <ref> <file>: added/modified line numbers of the work tree vs <ref>.
diff_lines() {
  git diff -U0 "$1" -- "$2" 2>/dev/null | while IFS= read -r hunk_line; do
    [[ "$hunk_line" == @@*@@* ]] || continue
    if [[ "$hunk_line" =~ \+([0-9]+)(,([0-9]+))? ]]; then
      local start="${BASH_REMATCH[1]}" count="${BASH_REMATCH[3]:-1}"
      [ "$count" -eq 0 ] && continue
      for ((i = 0; i < count; i++)); do echo $((start + i)); done
    fi
  done
}

# changed_lines_file <file>: writes changed line numbers (vs HEAD; mid-merge also vs MERGE_HEAD) to a temp file, prints its path.
changed_lines_file() {
  local f="$1" tmp
  tmp="$(mktemp)"
  tmpfiles+=("$tmp")
  if [ -n "$merging" ]; then
    comm -12 <(diff_lines HEAD "$f" | sort) <(diff_lines MERGE_HEAD "$f" | sort) > "$tmp"
  else
    diff_lines HEAD "$f" > "$tmp"
  fi
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
