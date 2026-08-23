#!/usr/bin/env bash
# usage: design-gate.sh <dir>
# Blocking check: runs Impeccable's deterministic detector (no LLM) over <dir>.
set -uo pipefail

DIR="${1:?usage: design-gate.sh <dir>}"
MAX_SHOWN=30
NOTICE="impeccable not available — install with npx impeccable install"

if ! command -v npx >/dev/null 2>&1; then
  echo "$NOTICE"
  exit 0
fi

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

npx -y impeccable detect --json --no-advisory "$DIR" >"$TMP_JSON" 2>/dev/null
STATUS=$?

# A real run always writes a JSON array; anything else (offline, unresolved
# package, corrupt output) means the tool itself is unavailable.
if ! python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d, list) else 1)' "$TMP_JSON" 2>/dev/null; then
  echo "$NOTICE"
  exit 0
fi

if [ "$STATUS" -eq 0 ]; then
  echo "design gate: clean (impeccable, 0 blocking findings)"
  exit 0
fi

python3 "$GATE_DIR/design-gate-format.py" "$TMP_JSON" "$MAX_SHOWN"
exit 1
