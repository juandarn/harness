#!/usr/bin/env bash
# Default `quality` gate: runs quality-pipeline.sh when the repo's stack has a shipped adapter
# (currently py). Stacks without an adapter are reported, not silently green.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

stack=""
for marker in pyproject.toml setup.py setup.cfg requirements.txt pytest.ini; do
  [ -f "$marker" ] && stack=py && break
done

if [ -z "$stack" ]; then
  echo "no quality adapter applies to this repo (no py markers) — nothing to run"
  exit 0
fi

[ -x "$ROOT/adapters/$stack/adapter.sh" ] || { echo "GATE BROKEN: adapter for '$stack' is missing" >&2; exit 1; }
HARNESS_LANG="$stack" exec "$HERE/quality-pipeline.sh" .
