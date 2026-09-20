#!/usr/bin/env bash
# Default `tests` gate: detects the repo's test runner(s) from marker files and runs them.
# A detected runner whose tool is missing BLOCKS; a repo with no runner has nothing to run.
set -uo pipefail

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "GATE BROKEN: '$1' is required to run this repo's tests. Install it — do not bypass." >&2
    exit 1
  }
}

ran=0
run() { ran=1; echo "+ $*"; "$@" || exit 1; }

if [ -f go.mod ]; then need go; run go test ./...; fi

if [ -f package.json ] && command -v jq >/dev/null 2>&1; then
  script="$(jq -r '.scripts.test // empty' package.json 2>/dev/null)"
  case "$script" in
    ""|*"no test specified"*) ;;
    *) need npm; run npm test --silent ;;
  esac
fi

if [ -x ./gradlew ]; then run ./gradlew test
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then need gradle; run gradle test; fi

if [ -f pom.xml ]; then need mvn; run mvn -q test; fi
if [ -f Cargo.toml ]; then need cargo; run cargo test --quiet; fi

if [ -f pytest.ini ] || [ -f pyproject.toml ] || [ -f setup.cfg ] || [ -f tox.ini ] || [ -f setup.py ] || [ -f requirements.txt ]; then
  hit="$(find . \( -name .venv -o -name venv -o -name node_modules -o -name .git \) -prune -o \
    \( -name 'test_*.py' -o -name '*_test.py' \) -print -quit)"
  if [ -n "$hit" ]; then
    need python3
    python3 -c 'import pytest' 2>/dev/null || { echo "GATE BROKEN: pytest is required (pip install pytest)." >&2; exit 1; }
    run python3 -m pytest -q
  fi
fi

for d in tests test; do
  if ls "$d"/*.bats >/dev/null 2>&1; then need bats; run bats "$d"; break; fi
done

[ "$ran" -eq 1 ] || echo "no test runner detected — nothing to run"
