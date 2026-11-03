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

# Go: test only packages touched by the staged change plus everything that transitively imports them.
# go.mod/go.sum/testdata (or no git) fall back to ./...; GO_GATE_DRY=1 prints the package list only.
go_pkgs() {
  local files
  files="$(git diff ${GO_GATE_DIFF_ARGS:---cached} --name-only --diff-filter=ACMR 2>/dev/null)" || { echo ./...; return; }
  if printf '%s\n' "$files" | rg -q '(^|/)(go\.mod|go\.sum)$|(^|/)testdata/'; then echo ./...; return; fi
  local dirs; dirs="$(printf '%s\n' "$files" | rg '\.go$' | xargs -n1 dirname 2>/dev/null | sort -u)"
  [ -n "$dirs" ] || return 0
  local top; top="$(git rev-parse --show-toplevel)"
  go list -f '{{.ImportPath}}|{{.Dir}}|{{join .Imports " "}} {{join .TestImports " "}} {{join .XTestImports " "}}' ./... |
    DIRS="$dirs" awk -F'|' -v top="$top" '
      BEGIN { n = split(ENVIRON["DIRS"], d, "\n"); for (i = 1; i <= n; i++) hit[top "/" d[i]] = 1 }
      { pkg[NR] = $1; k = split($3, im, " "); for (j = 1; j <= k; j++) rev[im[j]] = rev[im[j]] " " $1; if ($2 in hit) { q[++t] = $1; seen[$1] = 1 } }
      END { for (h = 1; h <= t; h++) { m = split(rev[q[h]], r, " "); for (j = 1; j <= m; j++) if (!(r[j] in seen)) { seen[r[j]] = 1; q[++t] = r[j] } }
            for (x in seen) print x }' | sort
}

go_test() {
  local pkgs out rc
  pkgs="$(go_pkgs)" || return 1
  [ -n "$pkgs" ] || { echo "go: no Go files staged — nothing to run"; return 0; }
  if [ -n "${GO_GATE_DRY:-}" ]; then printf '%s\n' "$pkgs"; exit 0; fi
  ran=1; echo "+ go test -p 2 ($(printf '%s\n' "$pkgs" | wc -l | tr -d ' ') pkg)"
  out="$(mktemp)"
  go test -p 2 $pkgs >"$out" 2>&1; rc=$?
  if [ "$rc" -ne 0 ]; then
    # keep the log short but name the failing test: FAIL lines, the indented assertion lines under them, panics, FAIL <pkg>
    awk '/^(=== RUN|--- PASS|ok |\?)/ {f=0; next}
         /^(--- FAIL|FAIL|panic:)/ {f=1; print; next}
         /^[ \t]/ && f {print; next}
         {f=0}' "$out" | head -n 60
    rm -f "$out"; exit 1
  fi
  tail -n 5 "$out"; rm -f "$out"
}

if [ -f go.mod ]; then need go; go_test || exit 1; fi

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
