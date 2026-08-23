#!/usr/bin/env python3
# usage: run_gates.py <gates.json> [cwd]
# Ported from rigor-harness gates/run_gates.py (unchanged logic).
import json
import os
import subprocess
import sys


def run_gate(gate, cwd):
    cmd = os.path.expandvars(gate["run"])
    result = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    return result.returncode == 0, (result.stdout + result.stderr).strip()


def main():
    if len(sys.argv) < 2:
        print("usage: run_gates.py <gates.json> [cwd]", file=sys.stderr)
        return 2
    config = json.load(open(sys.argv[1]))
    cwd = sys.argv[2] if len(sys.argv) > 2 else "."
    blocked, warned = [], []
    for gate in config.get("gates", []):
        name = gate["name"]
        severity = gate.get("severity", "block")
        ok, output = run_gate(gate, cwd)
        if ok:
            print(f"  pass   {name}")
        elif severity == "warn":
            warned.append(name)
            print(f"  WARN   {name} (advisory — does not block)")
        else:
            blocked.append(name)
            print(f"  BLOCK  {name}")
            for line in output.splitlines()[-4:]:
                print(f"           {line}")
    print()
    if blocked:
        print(f"harness gates: BLOCKED by {', '.join(blocked)}")
        return 1
    if warned:
        print(f"harness gates: passed with warnings ({', '.join(warned)})")
    else:
        print("harness gates: all green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
