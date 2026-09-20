#!/usr/bin/env python3
import subprocess
import sys

MUTATIONS = [
    ("//", "/"),
    (" + ", " - "),
    (" - ", " + "),
    (" * ", " + "),
    (" == ", " != "),
    (" != ", " == "),
    (" >= ", " > "),
    (" <= ", " < "),
    (" > ", " >= "),
    (" < ", " <= "),
    (" and ", " or "),
    (" or ", " and "),
    (" += ", " -= "),
    ("range(", "range(1 + "),
]


def mutants(source):
    lines = source.splitlines(keepends=True)
    out = []
    for i, line in enumerate(lines):
        for old, new in MUTATIONS:
            if old in line:
                mutated = lines[:]
                mutated[i] = line.replace(old, new, 1)
                out.append((i + 1, old.strip(), new.strip(), "".join(mutated)))
    return out


def run_tests(test_target):
    return subprocess.run(
        ["pytest", "-q", "-x", test_target], capture_output=True, text=True
    ).returncode


def score_mutants(module, test_target, candidates):
    original = open(module).read()
    killed, survivors = 0, []
    try:
        for lineno, old, new, mutant in candidates:
            open(module, "w").write(mutant)
            if run_tests(test_target) != 0:
                killed += 1
            else:
                survivors.append(f"line {lineno}: '{old}'->'{new}' survived")
    finally:
        open(module, "w").write(original)
    return killed, survivors


def main():
    module, test_target, min_kill = sys.argv[1], sys.argv[2], float(sys.argv[3])
    candidates = mutants(open(module).read())
    if not candidates:
        print("mutation: no mutable operators found")
        return 0
    killed, survivors = score_mutants(module, test_target, candidates)
    score = 100.0 * killed / len(candidates)
    print(f"mutation: killed {killed}/{len(candidates)} = {score:.1f}% (min {min_kill:.0f}%)")
    for s in survivors:
        print(f"  SURVIVOR {s}")
    if score < min_kill:
        print("MUTATION gate: tests do not catch enough mutations — weak tests", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
