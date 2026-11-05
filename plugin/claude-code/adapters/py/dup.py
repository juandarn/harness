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


BLOCK_LINES = 4


def diff_dup(changed, files):
    """(duplicated, total) over changed significant lines of non-test files; a changed line is
    duplicated when it sits in a window of BLOCK_LINES consecutive significant lines whose exact
    sequence also appears at another position in the staged non-test files."""
    seqs = {}
    windows = Counter()
    for f in files:
        if _is_test(f) or not f.endswith(".py") or f not in changed:
            continue
        with open(f) as fh:
            seq = [(n, ln.strip()) for n, ln in enumerate(fh, 1) if ln.strip() and not _is_trivial(ln.strip())]
        seqs[f] = seq
        for i in range(len(seq) - BLOCK_LINES + 1):
            windows[tuple(t for _, t in seq[i:i + BLOCK_LINES])] += 1
    dup = total = 0
    for f, seq in seqs.items():
        ls = set(changed[f])
        hot = set()
        for i in range(len(seq) - BLOCK_LINES + 1):
            if windows[tuple(t for _, t in seq[i:i + BLOCK_LINES])] > 1:
                hot.update(n for n, _ in seq[i:i + BLOCK_LINES])
        total += sum(1 for n, _ in seq if n in ls)
        dup += sum(1 for n, _ in seq if n in ls and n in hot)
    return dup, total


def main_diff():
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "gates"))
    import changed_lines
    max_pct, files = float(sys.argv[2]), sys.argv[3:]
    changed = changed_lines.changed()
    if changed is None:
        print("GATE BROKEN: not a git repo; cannot compute the change", file=sys.stderr)
        return 1
    dup, total = diff_dup(changed, files)
    if not total:
        print("duplication: 0.00% (no changed significant lines)")
        return 0
    pct = 100.0 * dup / total
    print(f"duplication: {pct:.2f}% of {total} changed lines (limit {max_pct:.2f}%)")
    if pct > max_pct:
        print("DRY gate: changed lines copy an existing block", file=sys.stderr)
        return 1
    return 0


def main():
    if sys.argv[1] == "--changed":
        return main_diff()
    targets, max_pct = sys.argv[1:-1], float(sys.argv[-1])
    lines = [ln for t in targets for ln in sig_lines(t)]
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
