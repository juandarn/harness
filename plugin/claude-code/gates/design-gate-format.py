#!/usr/bin/env python3
# usage: design-gate-format.py <findings.json> <max_shown>
# Formats impeccable's JSON findings as file:line [rule] snippet, capped.
import json
import sys


def main():
    findings_path, max_shown = sys.argv[1], int(sys.argv[2])
    findings = json.load(open(findings_path))
    print(f"design gate: {len(findings)} blocking finding(s)")
    for f in findings[:max_shown]:
        print(f"{f.get('file', '?')}:{f.get('line', 0)} [{f.get('antipattern', '?')}] {f.get('snippet', '')}")
    if len(findings) > max_shown:
        print(f"... and {len(findings) - max_shown} more")


if __name__ == "__main__":
    main()
