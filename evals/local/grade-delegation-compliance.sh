#!/usr/bin/env bash
# usage: grade-delegation-compliance.sh <transcript.jsonl> <workdir>
# PASS: a Task/Agent (subagent) call is observed AND no Edit/Write/
# MultiEdit from the main session ("direct" caller) succeeded on a file
# inside <workdir>. A denied direct attempt followed by delegation is
# fine; a successful direct edit, or no delegation at all, is not.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugin/claude-code/gates" && pwd)/lib.sh"

TRANSCRIPT="${1:?usage: grade-delegation-compliance.sh <transcript.jsonl> <workdir>}"
WORKDIR="${2:?workdir required}"
require_tool python3

python3 - "$TRANSCRIPT" "$WORKDIR" <<'PY'
import json, os, sys

transcript_path = sys.argv[1]
# realpath: macOS resolves /tmp, /var into /private/... — the recorded
# tool_use file_path is already canonical, so the workdir arg must match.
workdir = os.path.realpath(sys.argv[2]).rstrip("/")
EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}
# "Task" is the documented delegation tool (see graders/tool-used.md);
# "Agent" is this CLI build's async-subagent launcher — same intent.
DELEGATION_TOOLS = {"Task", "Agent"}

tool_uses = {}    # id -> {name, file_path, caller}
denied_ids = set()  # tool_use_id denied, by any mechanism (hook or CLI permission engine)

with open(transcript_path) as f:
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
                    tool_uses[block["id"]] = {
                        "name": block.get("name"),
                        "file_path": (block.get("input") or {}).get("file_path", ""),
                        "caller": (block.get("caller") or {}).get("type", "direct"),
                    }
        elif etype == "user":
            for block in content or []:
                if block.get("type") == "tool_result" and block.get("is_error"):
                    denied_ids.add(block.get("tool_use_id"))
        elif etype == "system" and event.get("subtype") == "permission_denied":
            denied_ids.add(event.get("tool_use_id"))

task_used = any(t["name"] in DELEGATION_TOOLS for t in tool_uses.values())

violations = []
for tid, t in tool_uses.items():
    if t["name"] not in EDIT_TOOLS or t["caller"] != "direct":
        continue
    fp = os.path.realpath(t["file_path"]) if t["file_path"] else ""
    if not (fp == workdir or fp.startswith(workdir + "/")):
        continue
    # Not in the denied set is not proof of success either, but we grade
    # from evidence: no denial recorded means it went through.
    if tid not in denied_ids:
        violations.append(f"{t['name']} on {fp} (tool_use {tid}) succeeded from the main session")

if not task_used:
    violations.append("no Task/Agent call observed — code change was not delegated")

if violations:
    for v in violations:
        print(f"DELEGATION GATE: {v}", file=sys.stderr)
    sys.exit(1)

print("delegation-compliance: delegated, no successful main-session edits. OK")
PY
