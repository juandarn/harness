#!/usr/bin/env python3
import os
import sys
from collections import Counter

_TRIVIAL_STARTS = ("#", "import ", "from ", '"""', "'''")
_TRIVIAL_EXACT = ("pass", "{", "}", "(", ")")


def _is_trivial(line):
    return line.startswith(_TRIVIAL_STARTS) or line in _TRIVIAL_EXACT


def _is_test(fp):
    base = os.path.basename(fp)
    return base.startswith("test_") or base.endswith("_test.py") or "/tests/" in fp


def _list_py(path):
    if os.path.isdir(path):
        return [os.path.join(r, f) for r, _, fs in os.walk(path) for f in fs if f.endswith(".py")]
    return [path] if path.endswith(".py") else []


def _significant(fp):
    out = []
    with open(fp) as fh:
        for ln in fh:
            norm = ln.strip()
            if norm and not _is_trivial(norm):
                out.append(norm)
    return out


def sig_lines(path):
    out = []
    for fp in _list_py(path):
        if not _is_test(fp):
            out.extend(_significant(fp))
    return out


def dup_pct(lines):
    counts = Counter(lines)
    repeated = [c for c in counts.values() if c > 1]
    duplicated = sum(repeated) - len(repeated)
    return 100.0 * duplicated / len(lines)


def main():
    target, max_pct = sys.argv[1], float(sys.argv[2])
    lines = sig_lines(target)
    if not lines:
        print("duplication: 0.00% (no significant lines)")
        return 0
    pct = dup_pct(lines)
    print(f"duplication: {pct:.2f}% (limit {max_pct:.2f}%)")
    if pct > max_pct:
        print("DRY gate: too much duplicated code", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
