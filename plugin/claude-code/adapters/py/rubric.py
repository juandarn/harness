#!/usr/bin/env python3
import ast
import io
import os
import sys
import tokenize


def is_test(path):
    base = os.path.basename(path)
    return base.startswith("test_") or base.endswith("_test.py") or "/tests/" in path


def py_files(target):
    if os.path.isdir(target):
        return [os.path.join(r, f) for r, _, fs in os.walk(target) for f in fs if f.endswith(".py")]
    return [target]


def complexity(node):
    score = 1
    for n in ast.walk(node):
        if isinstance(n, (ast.If, ast.For, ast.While, ast.ExceptHandler, ast.With, ast.comprehension)):
            score += 1
        elif isinstance(n, ast.BoolOp):
            score += len(n.values) - 1
        elif isinstance(n, ast.IfExp):
            score += 1
    return score


def _forbidden(src, path):
    issues = []
    for n in ast.walk(ast.parse(src)):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in ("eval", "exec"):
            issues.append(f"{path}: {n.func.id}() call")
    for tok in tokenize.generate_tokens(io.StringIO(src).readline):
        if tok.type == tokenize.COMMENT and ("TODO" in tok.string or "FIXME" in tok.string):
            issues.append(f"{path}: {tok.string.strip()}")
    return issues


def _scan_module(path, max_cx):
    src = open(path).read()
    public, over = [], []
    for n in ast.walk(ast.parse(src)):
        if isinstance(n, ast.FunctionDef):
            cx = complexity(n)
            if cx > max_cx:
                over.append(f"{n.name} (complexity {cx} > {max_cx})")
            if not n.name.startswith("_"):
                public.append(n.name)
    return public, over, _forbidden(src, path)


def _report(checks):
    failed = 0
    for label, violations in checks:
        if violations:
            failed += 1
            print(f"  FAIL  {label}")
            for v in violations:
                print(f"          - {v}")
        else:
            print(f"  pass  {label}")
    return failed


def main():
    target, max_cx = sys.argv[1], int(sys.argv[2])
    files = py_files(target)
    modules = [f for f in files if not is_test(f)]
    test_src = "\n".join(open(f).read() for f in files if is_test(f))
    public, over_complex, forbidden = [], [], []
    for f in modules:
        found, over, bad = _scan_module(f, max_cx)
        public += found
        over_complex += over
        forbidden += bad
    untested = [fn for fn in public if fn not in test_src]
    checks = [
        ("every public function is referenced by a test", untested),
        (f"no function exceeds complexity {max_cx}", over_complex),
        ("no forbidden patterns (eval/exec/TODO/FIXME)", forbidden),
    ]
    failed = _report(checks)
    if failed:
        print(f"rubric: {failed} criterion/criteria failed", file=sys.stderr)
        return 1
    print("rubric: all criteria pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
