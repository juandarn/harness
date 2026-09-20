import pytest

from money import allocate, format_cents


def test_allocate_splits_evenly():
    assert allocate(100, [1, 1]) == [50, 50]


def test_allocate_never_loses_cents():
    parts = allocate(100, [1, 1, 1])
    assert sum(parts) == 100
    assert parts == [34, 33, 33]


def test_allocate_distributes_remainder_to_earliest():
    assert allocate(5, [3, 7]) == [2, 3]


def test_allocate_by_weights():
    parts = allocate(1000, [1, 2, 2])
    assert sum(parts) == 1000
    assert parts == [200, 400, 400]


def test_allocate_rejects_non_positive_total():
    with pytest.raises(ValueError):
        allocate(0, [1, 1])


def test_allocate_rejects_non_integer_total():
    with pytest.raises(ValueError):
        allocate(100.5, [1, 1])


def test_allocate_rejects_empty_ratios():
    with pytest.raises(ValueError):
        allocate(100, [])


def test_allocate_rejects_zero_sum_ratios():
    with pytest.raises(ValueError):
        allocate(100, [0, 0])


def test_allocate_rejects_negative_ratio():
    with pytest.raises(ValueError):
        allocate(100, [3, -1])


def test_allocate_rejects_non_integer_ratio():
    with pytest.raises(ValueError):
        allocate(100, [1.5, 2])


def test_format_cents_default_usd():
    assert format_cents(12345) == "$123.45"


def test_format_cents_zero():
    assert format_cents(0) == "$0.00"


def test_format_cents_currency_symbol():
    assert format_cents(500, symbol="€") == "€5.00"


def test_format_cents_large_amount_is_exact():
    assert format_cents(1000000000000000001) == "$10000000000000000.01"


def test_format_cents_negative():
    assert format_cents(-12345) == "-$123.45"


def test_allocate_remainder_skips_zero_weight():
    assert allocate(1, [0, 1, 1]) == [0, 1, 0]
    assert allocate(2, [0, 1, 2]) == [0, 1, 1]


def test_allocate_rejects_bool_total():
    with pytest.raises(ValueError):
        allocate(True, [1, 1])


def test_format_cents_rejects_non_integer():
    with pytest.raises(ValueError):
        format_cents(10.5)
