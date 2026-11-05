#!/usr/bin/env python3
"""The one definition of "the change": files and added/modified lines of `git diff $GATE_DIFF_ARGS`."""
import json
import os
import re
import shlex
import subprocess
import sys

_HUNK = re.compile(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@")


def _diff(*extra):
    args = shlex.split(os.environ.get("GATE_DIFF_ARGS") or "--cached")
    cmd = ["git", "-c", "core.quotepath=off", "diff", *args, "--no-color", "--no-ext-diff",
           "--relative", "--diff-filter=ACMR", "--src-prefix=a/", "--dst-prefix=b/", *extra]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout if res.returncode == 0 else None


def changed():
    """{file: [changed line numbers]} for added/copied/modified/renamed files, or None outside git."""
    names = _diff("--name-only")
    body = _diff("-U0")
    if names is None or body is None:
        return None
    out = {n: [] for n in names.splitlines() if n}
    cur = None
    for ln in body.splitlines():
        if ln.startswith("+++ "):
            cur = ln[6:] if ln.startswith("+++ b/") else None
        elif cur in out:
            m = _HUNK.match(ln)
            if m:
                start, count = int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1)
                out[cur].extend(range(start, start + count))
    return out


if __name__ == "__main__":
    res = changed()
    if res is None:
        sys.exit(1)
    if "--files" in sys.argv[1:]:
        print("\n".join(res))
    else:
        print(json.dumps(res))
