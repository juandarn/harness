#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/gates/lib.sh"

VERB="${1:?verb}"; shift
[ $# -gt 0 ] || { red "usage: adapter.sh <verb> <file>..."; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(py_interp)"; export PY
need_mod() { "$PY" -c "import $1" 2>/dev/null || { red "GATE BROKEN: python module '$1' is missing for $PY. Run bin/doctor.sh — do not bypass."; exit 1; }; }

case "$VERB" in
  format|lint) require_tool ruff;   python3 "$HERE/scoped.py" "$VERB" "$@" ;;
  security)    require_tool bandit; python3 "$HERE/scoped.py" security "$@" ;;
  test)        need_mod pytest;     python3 "$HERE/scoped.py" test "$@" ;;
  coverage)    need_mod pytest; need_mod coverage
               COVERAGE_MIN="$(threshold coverage_min)" python3 "$HERE/scoped.py" coverage "$@" ;;
  duplication) python3 "$HERE/dup.py" --changed "$(threshold duplication_max_pct)" "$@" ;;
  *)           red "unknown verb: $VERB"; exit 2 ;;
esac
