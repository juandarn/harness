#!/usr/bin/env bash
# usage: tdd-proof.sh [transcript.jsonl]   (reads stdin if omitted)
# Offline transcript grader for evals/local (live enforcement: pre-edit-tdd-gate.sh + post-bash-test-recorder.sh).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TRANSCRIPT="${1:-/dev/stdin}"
require_tool python3

python3 - "$TRANSCRIPT" <<'PY'
import json, re, sys

CODE = re.compile(r'\.(go|kt|kts|ts|tsx|js|jsx|py)$')
TESTPATH = re.compile(r'(_test\.|\.test\.|\.spec\.|/tests?/|/__tests__/|test_)')
TESTCMD = re.compile(r'\b(go test|gradle .*test|pytest|vitest|jest|npm (run )?test)\b')

events = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line:
            events.append(json.loads(line))

first_test_edit = first_src_edit = None
red_seen = green_seen = False
for i, e in enumerate(events):
    kind, payload = e.get("tool"), e.get("path", "")
    if kind in ("Write", "Edit") and CODE.search(payload):
        if TESTPATH.search(payload):
            if first_test_edit is None:
                first_test_edit = i
        elif first_src_edit is None:
            first_src_edit = i
    if kind == "Bash" and TESTCMD.search(e.get("cmd", "")):
        if e.get("exit", 0) != 0 and first_src_edit is None:
            red_seen = True          # a test failed before any source existed
        elif e.get("exit", 0) == 0 and red_seen:
            green_seen = True        # ...and later passed

def block(msg):
    print(f"TDD GATE (strict): {msg}", file=sys.stderr)
    sys.exit(1)

if first_src_edit is None:
    sys.exit(0)  # no source touched, nothing to gate
if first_test_edit is None:
    block("source changed but no test was written. Write the test first.")
if first_test_edit > first_src_edit:
    block("source was written before its test. That is code-first, not TDD. "
          "Write the test, watch it fail (RED), then implement.")
if not red_seen:
    block("no test was observed failing before implementation. "
          "You cannot prove RED -> GREEN without a RED.")
if not green_seen:
    block("test never went from RED to GREEN. Finish the cycle.")
print("TDD proof: RED before source, GREEN after. OK")
PY
