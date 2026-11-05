#!/usr/bin/env python3
"""Prints the pytest targets affected by the staged change: `FULL`, or one test path per line."""
import fnmatch
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "gates"))
import changed_lines  # noqa: E402

FULL_NAMES = {"conftest.py", "pytest.ini", "pyproject.toml", "setup.cfg", "tox.ini", "setup.py"}
PRUNE = {".venv", "venv", "node_modules", ".git"}


def is_test(path):
    base = os.path.basename(path)
    return base.endswith(".py") and (base.startswith("test_") or base.endswith("_test.py"))


def _stem(path):
    stem = os.path.splitext(os.path.basename(path))[0]
    return os.path.basename(os.path.dirname(path)) if stem == "__init__" else stem


def _all_tests(root):
    for r, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in PRUNE]
        for f in files:
            if is_test(f):
                yield os.path.normpath(os.path.join(r, f))


def select(changed, root="."):
    names = list(changed)
    for n in names:
        base = os.path.basename(n)
        if base in FULL_NAMES or fnmatch.fnmatch(base, "requirements*.txt"):
            return "FULL"
    picked = {os.path.normpath(n) for n in names if n.endswith(".py") and is_test(n)}
    stems = {_stem(n) for n in names if n.endswith(".py") and not is_test(n)} - {""}
    if stems:
        pat = re.compile(r"\b(?:%s)\b" % "|".join(re.escape(s) for s in sorted(stems)))
        for t in _all_tests(root):
            with open(t, errors="ignore") as fh:
                if pat.search(fh.read()):
                    picked.add(t)
    return sorted(picked)


def main():
    ch = changed_lines.changed()
    sel = "FULL" if ch is None else select(ch)
    print(sel if sel == "FULL" else "\n".join(sel))
    return 0


if __name__ == "__main__":
    sys.exit(main())
