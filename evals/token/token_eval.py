#!/usr/bin/env python3
"""Token-cost eval of harness session settings against the installed Claude Code config.

Arms differ only by a --settings overlay (env vars + autoCompactWindow), so every
run uses the real plugins and hooks. Two modes:

  tasks  short repo tasks (bugfix, feature, rename, trace, question, big-file fix)
  long   one session of 14 sequential turns (--resume) over ~1.2k-line modules,
         so context grows the way it does in real work

Metric: total input tokens (fresh + cache write + cache read) over every model,
subagents included, plus cost and an executable pass check.

Usage: python token_eval.py tasks|long REPS [ARM ...]
"""
import json, os, re, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
MODE, REPS = sys.argv[1], int(sys.argv[2])
MODEL = os.environ.get("EVAL_MODEL", "opus")
OUT = os.path.join(HERE, f"results-{MODE}.jsonl")
TESTS = "python3 -m unittest discover -s tests -t . -q"

ARMS = {
    "old": {"env": {"HARNESS_INLINE_OK": "0", "HARNESS_READ_GATE": "0"}, "autoCompactWindow": 1000000},
    "new-gate": {"env": {"HARNESS_INLINE_OK": "1", "HARNESS_READ_GATE": "1", "BASH_MAX_OUTPUT_LENGTH": "12000"},
                 "autoCompactWindow": 200000},
    "new-native": {"env": {"HARNESS_INLINE_OK": "1", "HARNESS_READ_GATE": "0", "BASH_MAX_OUTPUT_LENGTH": "12000",
                           "CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS": "6000"}, "autoCompactWindow": 200000},
}
ARMS["compact-only"] = {"env": {"HARNESS_INLINE_OK": "0", "HARNESS_READ_GATE": "0"}, "autoCompactWindow": 200000}
SELECTED = sys.argv[3:] or list(ARMS)
W = {"in": 1, "cw": 2, "cr": 0.1, "out": 5}  # Anthropic price ratios vs base input

TASKS = {
    "bugfix": ("The tests in tests/test_pricing.py fail. Find and fix the bug.", TESTS),
    "feature": ("Add export_orders_csv(orders, path) to shop/reports.py. It writes a CSV with header "
                "id,customer,total and one row per order. Add a test for it.", TESTS),
    "rename": ("Rename the function calc_total to compute_total everywhere in the codebase.",
               TESTS + " && ! grep -rn calc_total shop tests"),
    "tracebug": ("Customers who enter their country in lowercase (for example 'co') are charged no tax. "
                 "Fix it and add a regression test.", TESTS),
    "question": ("Which file defines the tax rate for Colombia, and what is the value? Answer in one line, "
                 "do not change any file.", "grep -q settings.py $RESULT && grep -q 0.19 $RESULT && git diff --quiet"),
    "bigfile": ("tests/test_legacy_1.py fails. Fix the bug.", TESTS),
}
LONG_TURNS = 14
# Real sessions grow through big tool outputs (logs, SQL, diffs). Each long turn pulls ~20k tokens.
LONG_PROMPT = ("Run `sed -n '1,700p' shop/legacy_{k}.py` with Bash (one call, full output, no head/grep), then "
               "fix net_amount_{k} so tests/test_legacy_{k}.py passes. Touch only that module. Reply in one line.")


def transcript_usage(work, sid):
    """Sum per-request usage from the session transcript (and its subagents), deduped by request id.
    The -p JSON reports cumulative totals on --resume, so summing it per turn double counts."""
    proj = os.path.expanduser("~/.claude/projects/" + re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(work)))
    files = [os.path.join(proj, f"{sid}.jsonl")]
    sub = os.path.join(proj, sid, "subagents")
    if os.path.isdir(sub):
        files += [os.path.join(sub, f) for f in os.listdir(sub) if f.endswith(".jsonl")]
    seen, t = set(), {"input": 0, "weighted": 0.0, "requests": 0, "max_ctx": 0, "compactions": 0}
    for f in files:
        if not os.path.exists(f):
            continue
        for line in open(f):
            if '"compact_boundary"' in line:
                t["compactions"] += 1
            if '"usage"' not in line:
                continue
            try:
                d = json.loads(line); m = d["message"]; u = m["usage"]
            except Exception:
                continue
            rid = d.get("requestId") or m.get("id")
            if d.get("type") != "assistant" or rid in seen:
                continue
            seen.add(rid)
            i, cw, cr, o = (u.get(k, 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"))
            t["input"] += i + cw + cr; t["requests"] += 1; t["max_ctx"] = max(t["max_ctx"], i + cw + cr)
            t["weighted"] += i * W["in"] + cw * W["cw"] + cr * W["cr"] + o * W["out"]
    return t


def fixture(bug, legacy):
    work = tempfile.mkdtemp(prefix="tokeval-")
    subprocess.run([sys.executable, os.path.join(HERE, "make_fixture.py"), work] + (["--bug"] if bug else []), check=True)
    if legacy:
        subprocess.run([sys.executable, os.path.join(HERE, "legacy.py"), work, str(legacy)], check=True)
    for cmd in (["git", "init", "-q"], ["git", "add", "-A"],
                ["git", "-c", "user.email=e@e", "-c", "user.name=e", "commit", "-qm", "init"]):
        subprocess.run(cmd, cwd=work, check=True)
    return work


def claude(prompt, arm, work, resume=None):
    cmd = ["claude", "-p", prompt, "--model", MODEL, "--output-format", "json", "--strict-mcp-config",
           "--permission-mode", "bypassPermissions", "--max-turns", "40", "--settings", json.dumps(ARMS[arm])]
    if resume:
        cmd += ["--resume", resume]
    try:
        return json.loads(subprocess.run(cmd, cwd=work, capture_output=True, text=True, timeout=1500).stdout)
    except Exception as e:
        return {"result": f"ERROR {e}"}


def usage(d):
    mu = d.get("modelUsage") or {}
    tok = lambda k: sum(m.get(k, 0) for m in mu.values())
    return {"input": tok("inputTokens") + tok("cacheCreationInputTokens") + tok("cacheReadInputTokens"),
            "output": tok("outputTokens"), "cost": d.get("total_cost_usd", 0) or 0,
            "turns": d.get("num_turns", 0) or 0, "models": sorted(mu)}


def check(work, cmd, result=""):
    path = os.path.join(work, ".result")
    with open(path, "w") as f:
        f.write(result)
    return subprocess.run(["bash", "-c", cmd], cwd=work, capture_output=True,
                          env=dict(os.environ, RESULT=path)).returncode == 0


def record(row):
    with open(OUT, "a") as f:
        f.write(json.dumps(row) + "\n")
    print(json.dumps(row), flush=True)


def run_task(arm, task, rep):
    prompt, cmd = TASKS[task]
    work = fixture(task == "bugfix", 1 if task == "bigfile" else 0)
    try:
        d = claude(prompt, arm, work)
        record({"arm": arm, "task": task, "rep": rep, "pass": check(work, cmd, d.get("result") or ""), **usage(d)})
    finally:
        shutil.rmtree(work, ignore_errors=True)


def run_long(arm, rep):
    work = fixture(False, LONG_TURNS)
    try:
        sid = None
        for k in range(1, LONG_TURNS + 1):
            d = claude(LONG_PROMPT.format(k=k), arm, work, sid)
            sid = d.get("session_id") or sid
        tests = [check(work, f"python3 -m unittest tests.test_legacy_{k} -q") for k in range(1, LONG_TURNS + 1)]
        record({"arm": arm, "task": "long", "rep": rep, "pass": all(tests), "fixed": sum(tests),
                **transcript_usage(work, sid)})
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    open(OUT, "w").close()
    if MODE == "tasks":
        jobs = [(a, t, r) for r in range(REPS) for t in TASKS for a in SELECTED]
        with ThreadPoolExecutor(int(os.environ.get("EVAL_PARALLEL", "6"))) as ex:
            list(ex.map(lambda j: run_task(*j), jobs))
    else:
        with ThreadPoolExecutor(len(SELECTED) * REPS) as ex:
            list(ex.map(lambda j: run_long(*j), [(a, r) for r in range(REPS) for a in SELECTED]))
