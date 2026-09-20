#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/gates/lib.sh"

VERB="${1:?verb}"; TARGET="${2:?target}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$VERB" in
  format)      require_tool ruff;    ruff format --check "$TARGET" ;;
  lint)        require_tool ruff;    ruff check "$TARGET" ;;
  test)        require_tool pytest;  pytest -q "$TARGET" ;;
  coverage)    require_tool coverage
               coverage run --source="$TARGET" -m pytest -q "$TARGET" >/dev/null
               coverage report --fail-under="$(threshold coverage_min)" ;;
  duplication) python3 "$HERE/dup.py" "$TARGET" "$(threshold duplication_max_pct)" ;;
  security)    require_tool bandit;  bandit -q -r "$TARGET" -x '*/test_*.py,*/*_test.py,*/tests/*' ;;
  *)           red "unknown verb: $VERB"; exit 2 ;;
esac
