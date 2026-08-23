#!/usr/bin/env bash
# usage: grade-comment-restraint.sh <transcript.jsonl> <workdir>
# PASS: gates/comment-nag.sh finds no violation in any file created or
# modified since the seed commit in <workdir>. Grades the workdir
# directly (per spec) — the transcript arg is accepted for interface
# symmetry with the other graders but not parsed.
set -euo pipefail
GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugin/claude-code/gates" && pwd)"
source "$GATES_DIR/lib.sh"

TRANSCRIPT="${1:?usage: grade-comment-restraint.sh <transcript.jsonl> <workdir>}"
WORKDIR="${2:?workdir required}"
require_tool git

cd "$WORKDIR"
ROOT_COMMIT="$(git rev-list --max-parents=0 HEAD | tail -1)"

mapfile -t CHANGED < <(
  { git diff --name-only "$ROOT_COMMIT" --
    git status --porcelain --no-renames | awk '$1=="??"{print $2}'
  } | sort -u
)

violations=0
for f in "${CHANGED[@]}"; do
  [ -f "$f" ] || continue
  if ! OUT="$("$GATES_DIR/comment-nag.sh" "$f" 2>&1)"; then
    echo "$OUT" >&2
    violations=1
  fi
done

if [ "$violations" -eq 1 ]; then
  echo "COMMENT GATE: one or more changed files failed comment-nag" >&2
  exit 1
fi

echo "comment-restraint: no comment-nag violations in changed files. OK"
