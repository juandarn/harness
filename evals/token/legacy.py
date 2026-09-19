#!/usr/bin/env python3
"""Add large legacy modules (~1.2k lines each) with one planted bug per module.

Whole-file reads of these are expensive, so they separate agents that grep and
read ranges from agents that dump files. Usage: python legacy.py DEST N
"""
import os, sys, textwrap

FILLER = '''
def helper_{k}_{i}(rows, key="amount", scale=1.0):
    """Aggregate `key` over rows for report section {i}."""
    total = 0.0
    for row in rows:
        value = row.get(key, 0) or 0
        if value < 0:
            continue
        total += value * scale
    return round(total, 2)

'''
TARGET = '''
def net_amount_{k}(gross, fee_pct):
    """Return gross minus a fee of `fee_pct` percent, rounded to cents."""
    return round(gross * (1 + fee_pct / 100), 2)

'''
TEST = '''
import unittest
from shop.legacy_{k} import net_amount_{k}


class Legacy{k}Test(unittest.TestCase):
    def test_net_amount(self):
        self.assertEqual(net_amount_{k}(200.0, 10), 180.0)
'''


def main(dest, n):
    for k in range(1, n + 1):
        parts = [FILLER.format(k=k, i=i) for i in range(110)]
        parts.insert(70 + k, TARGET.format(k=k))
        with open(os.path.join(dest, "shop", f"legacy_{k}.py"), "w") as f:
            f.write('"""Legacy billing reports, module %d."""\n' % k + "".join(parts))
        with open(os.path.join(dest, "tests", f"test_legacy_{k}.py"), "w") as f:
            f.write(textwrap.dedent(TEST.format(k=k)).lstrip())


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]))
