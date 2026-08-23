#!/usr/bin/env bash
# usage: grade-tdd-order.sh <transcript.jsonl> <workdir>
# Transforms the transcript into gates/tdd-proof.sh's input contract
# ({"tool":"Write"/"Edit","path":..} / {"tool":"Bash","cmd":..,"exit":..})
# and defers the verdict to that gate's exit code. Only successful (not
# denied) Write/Edit calls are fed in — a denied attempt never happened.
#
# Caveat: this only sees main-session tool calls. If the delegation gate
# pushes all edits into a subagent, those edits are invisible here; see
# evals/README.md.
set -euo pipefail
GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugin/claude-code/gates" && pwd)"
source "$GATES_DIR/lib.sh"

TRANSCRIPT="${1:?usage: grade-tdd-order.sh <transcript.jsonl> <workdir>}"
WORKDIR="${2:?workdir required}"
require_tool python3

NORMALIZED="$(mktemp)"
trap 'rm -f "$NORMALIZED"' EXIT

python3 - "$TRANSCRIPT" > "$NORMALIZED" <<'PY'
import json, sys

tool_uses = []  # ordered, each dict mutated in place with its result
by_id = {}

def mark_denied(tool_use_id):
    tu = by_id.get(tool_use_id)
    if tu is not None:
        tu["_is_error"] = True

with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        event = json.loads(line)
        etype = event.get("type")
        message = event.get("message")
        content = message.get("content") if isinstance(message, dict) else []
        if etype == "assistant":
            for block in content or []:
                if block.get("type") == "tool_use":
                    tool_uses.append(block)
                    by_id[block["id"]] = block
        elif etype == "user":
            for block in content or []:
                if block.get("type") == "tool_result" and block.get("is_error"):
                    mark_denied(block.get("tool_use_id"))
        elif etype == "system" and event.get("subtype") == "permission_denied":
            mark_denied(event.get("tool_use_id"))

for tu in tool_uses:
    name = tu.get("name")
    inp = tu.get("input") or {}
    if name in ("Write", "Edit", "MultiEdit"):
        if tu.get("_is_error"):
            continue  # denied/failed edit never happened; don't feed it in
        path = inp.get("file_path", "")
        if path:
            print(json.dumps({"tool": "Edit", "path": path}))
    elif name == "Bash":
        exit_code = 1 if tu.get("_is_error") else 0
        print(json.dumps({"tool": "Bash", "cmd": inp.get("command", ""), "exit": exit_code}))
PY

"$GATES_DIR/tdd-proof.sh" "$NORMALIZED"
