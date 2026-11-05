#!/usr/bin/env bash
# Stack-agnostic quality gate. Stops at the first red. Each stage delegates to
# the language adapter resolved from the target file's extension, so the
# pipeline itself never branches on language.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[ $# -gt 0 ] || { echo "usage: quality-pipeline.sh <file>..." >&2; exit 2; }
STACK="${HARNESS_LANG:-$("$HARNESS_ROOT/bin/detect-lang.sh" "$1")}"
ADAPTER="$HARNESS_ROOT/adapters/$STACK/adapter.sh"
[ -x "$ADAPTER" ] || { red "No adapter for language '$STACK'"; exit 1; }

STAGES=(format lint test coverage duplication security)
for stage in "${STAGES[@]}"; do
  printf '  %-12s ' "$stage"
  if out=$("$ADAPTER" "$stage" "$@" 2>&1); then
    grn "pass"
  else
    red "FAIL"
    printf '%s\n' "$out" | sed 's/^/    /'
    red "Gate red at stage '$stage'. Commit blocked."
    exit 1
  fi
done
grn "quality gate: all green"
