#!/usr/bin/env python3
"""Diff-scoped py gate stages: a stage fails only on findings that sit on changed lines."""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "gates"))
import changed_lines  # noqa: E402
import select_tests  # noqa: E402


def _run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def _ranges(lines):
    out = []
    for n in sorted(set(lines)):
        if out and n == out[-1][1] + 1:
            out[-1][1] = n
        else:
            out.append([n, n])
    return out


def _by_real(changed):
    return {os.path.realpath(f): (f, set(ls)) for f, ls in changed.items()}


def fmt(changed):
    bad = []
    for f, lines in changed.items():
        for s, e in _ranges(lines):
            r = _run(["ruff", "format", "--check", "--force-exclude", "--range", f"{s}-{e}", f])
            if r.returncode != 0:
                bad.append(f"{f}:{s}-{e} would be reformatted\n{r.stdout}{r.stderr}")
    return bad


def lint(changed):
    r = _run(["ruff", "check", "--output-format", "json", "--force-exclude", "--no-cache", *changed])
    try:
        diags = json.loads(r.stdout or "[]")
    except ValueError:
        return [f"ruff check failed:\n{r.stdout}{r.stderr}"]
    real = _by_real(changed)
    bad = []
    for d in diags:
        rel, ls = real.get(os.path.realpath(d["filename"]), (None, set()))
        row = d["location"]["row"]
        if row in ls:
            bad.append(f"{rel}:{row}: {d['code']} {d['message']}")
    return bad


def security(changed):
    files = [f for f in changed if not select_tests.is_test(f) and "/tests/" not in "/" + f]
    if not files:
        return []
    r = _run(["bandit", "-q", "-f", "json", *files])
    try:
        res = json.loads(r.stdout)["results"]
    except (ValueError, KeyError):
        return [f"bandit failed:\n{r.stdout}{r.stderr}"]
    real = _by_real(changed)
    bad = []
    for i in res:
        rel, ls = real.get(os.path.realpath(i["filename"]), (None, set()))
        if i["line_number"] in ls:
            bad.append(f"{rel}:{i['line_number']}: {i['test_id']} {i['issue_text']}")
    return bad


def _selected(changed):
    sel = select_tests.select(changed)
    return [] if sel == "FULL" else sel, sel == "FULL"


def tests(changed):
    sel, full = _selected(changed)
    if not sel and not full:
        print("python: no affected tests — nothing to run")
        return []
    r = _run([os.environ["PY"], "-m", "pytest", "-q", *sel])
    return [r.stdout + r.stderr] if r.returncode != 0 else []


def coverage(changed):
    prod = {f: ls for f, ls in changed.items() if not select_tests.is_test(f) and ls}
    if not prod:
        print("coverage: no changed executable lines")
        return []
    sel, full = _selected(changed)
    py = os.environ["PY"]
    with tempfile.TemporaryDirectory() as tmp:
        data, out, empty = (os.path.join(tmp, n) for n in ("data", "cov.json", "empty.py"))
        if sel or full:
            run = [py, "-m", "coverage", "run", "--source=.", "--data-file", data, "-m", "pytest", "-q", *sel]
        else:
            open(empty, "w").close()
            run = [py, "-m", "coverage", "run", "--source=.", "--data-file", data, empty]
        r = _run(run)
        if r.returncode != 0:
            return [r.stdout + r.stderr]
        inc = ",".join(os.path.abspath(f) for f in prod)
        r = _run([py, "-m", "coverage", "json", "--data-file", data, "-o", out, "--include", inc])
        if r.returncode != 0:
            return [r.stdout + r.stderr]
        with open(out) as fh:
            files = json.load(fh)["files"]
    real = _by_real(prod)
    covered = total = 0
    for k, v in files.items():
        _, ls = real.get(os.path.realpath(k), (None, set()))
        hit, miss = set(v["executed_lines"]) & ls, set(v["missing_lines"]) & ls
        covered, total = covered + len(hit), total + len(hit) + len(miss)
    if total == 0:
        print("coverage: no changed executable lines")
        return []
    pct = 100.0 * covered / total
    minimum = float(os.environ["COVERAGE_MIN"])
    print(f"diff coverage: {pct:.1f}% ({covered}/{total} changed lines, minimum {minimum:g}%)")
    return [] if pct >= minimum else ["diff coverage below minimum"]


STAGES = {"format": fmt, "lint": lint, "security": security, "test": tests, "coverage": coverage}


def main():
    verb = sys.argv[1]
    ch = changed_lines.changed()
    if ch is None:
        print("GATE BROKEN: not a git repo; cannot compute the change", file=sys.stderr)
        return 1
    wanted = set(sys.argv[2:])
    changed = {f: ls for f, ls in ch.items() if f in wanted and f.endswith(".py")}
    bad = STAGES[verb](changed)
    for b in bad:
        print(b, file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
