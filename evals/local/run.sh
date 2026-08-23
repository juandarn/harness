#!/usr/bin/env bash
# usage: run.sh [--case <name>] [--model <model>]
# Local stand-in for `claude plugin eval` (early access, not runnable on
# this account yet). Runs each case's prompt headlessly against a fresh
# seed repo, then grades the transcript with the plugin's own deterministic
# gates — never from the model's self-report.
set -euo pipefail

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVALS_DIR="$(dirname "$LOCAL_DIR")"
GATES_DIR="$(cd "$EVALS_DIR/../plugin/claude-code/gates" && pwd)"
source "$GATES_DIR/lib.sh"

ALL_CASES=(delegation-compliance comment-restraint tdd-order)
CASE=""
MODEL="haiku"

while [ $# -gt 0 ]; do
  case "$1" in
    --case) CASE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    *) red "unknown arg: $1"; exit 2 ;;
  esac
done

require_tool claude
require_tool git
require_tool jq
require_tool python3

CASES=("${ALL_CASES[@]}")
if [ -n "$CASE" ]; then
  CASES=("$CASE")
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
RESULTS_DIR="$LOCAL_DIR/results/$TS"
mkdir -p "$RESULTS_DIR"
RESULTS_JSON="$RESULTS_DIR/results.json"
echo "[]" > "$RESULTS_JSON"

# frontmatter_field <prompt.md> <key> -> value on the line "key: value"
frontmatter_field() {
  awk -v f="$2" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { exit }
    infm && $0 ~ "^"f":" { sub("^"f":[ \t]*", ""); print; exit }
  ' "$1"
}

# prompt_body <prompt.md> -> everything after the second "---" line
prompt_body() {
  awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$1"
}

create_seed_repo() {
  local dir="$1"
  mkdir -p "$dir/src"
  git -C "$dir" init -q
  git -C "$dir" config user.email "eval@local"
  git -C "$dir" config user.name "harness-eval"
  cat > "$dir/src/utils.py" <<'PY'
def clamp(value, low, high):
    return max(low, min(value, high))
PY
  cat > "$dir/src/test_utils.py" <<'PY'
from utils import clamp


def test_clamp_within_range():
    assert clamp(5, 0, 10) == 5
PY
  cat > "$dir/README.md" <<'MD'
# eval-seed

Minimal seed repo for a harness local eval run.
MD
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "seed"
}

print_row() {
  printf "%-24s %-6s %6ss\n" "$1" "$2" "$3"
}

append_result() {
  local tmp
  tmp="$(mktemp)"
  jq --arg case "$1" --arg verdict "$2" --argjson duration "$3" --arg evidence "$4" \
    '. += [{"case":$case,"verdict":$verdict,"duration_s":$duration,"evidence":$evidence}]' \
    "$RESULTS_JSON" > "$tmp" && mv "$tmp" "$RESULTS_JSON"
}

run_case() {
  local name="$1"
  local prompt_file="$EVALS_DIR/$name/prompt.md"
  local grader="$LOCAL_DIR/grade-${name}.sh"

  if [ ! -f "$prompt_file" ]; then
    print_row "$name" "ERROR" 0
    append_result "$name" "ERROR" 0 "no prompt.md for $name"
    return
  fi

  local max_turns
  max_turns="$(frontmatter_field "$prompt_file" max_turns)"
  max_turns="${max_turns:-10}"

  local repo_dir
  repo_dir="$(mktemp -d "${TMPDIR:-/tmp}/harness-eval-${name}.XXXXXX")"
  create_seed_repo "$repo_dir"

  local transcript="$RESULTS_DIR/${name}.jsonl"
  local start end duration
  start=$(date +%s)
  (
    cd "$repo_dir" && claude -p "$(prompt_body "$prompt_file")" \
      --model "$MODEL" \
      --max-turns "$max_turns" \
      --permission-mode bypassPermissions \
      --output-format stream-json \
      --include-hook-events \
      --verbose
  ) > "$transcript" 2> "$RESULTS_DIR/${name}.stderr.log" || true
  end=$(date +%s)
  duration=$((end - start))

  local verdict evidence
  if [ ! -x "$grader" ]; then
    verdict="ERROR"
    evidence="no grader at $grader"
  elif evidence="$("$grader" "$transcript" "$repo_dir" 2>&1)"; then
    verdict="PASS"
  else
    verdict="FAIL"
  fi

  print_row "$name" "$verdict" "$duration"
  append_result "$name" "$verdict" "$duration" "$evidence"
  echo "  workdir: $repo_dir" >&2
}

printf "%-24s %-6s %6s\n" "CASE" "VERDICT" "TIME"
FAILED=0
for c in "${CASES[@]}"; do
  run_case "$c" || FAILED=1
done

echo
echo "results: $RESULTS_JSON"

if jq -e 'any(.[]; .verdict != "PASS")' "$RESULTS_JSON" >/dev/null; then
  FAILED=1
fi

[ "$FAILED" -eq 0 ] && grn "all cases PASS" || red "one or more cases did not PASS"
exit "$FAILED"
