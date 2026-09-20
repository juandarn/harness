#!/usr/bin/env bash
# Default `comment-restraint` gate: runs comment-nag.sh over every file changed vs HEAD
# (staged, unstaged and untracked). Outside a git work tree there is nothing to compare.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo — nothing to check"; exit 0; }

files="$( { git diff --name-only HEAD 2>/dev/null || git diff --name-only --cached; git ls-files --others --exclude-standard; } | sort -u)"

status=0
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  "$HERE/comment-nag.sh" "$f" || status=1
done <<EOF
$files
EOF

[ "$status" -eq 0 ] && echo "comment restraint ok"
exit "$status"
