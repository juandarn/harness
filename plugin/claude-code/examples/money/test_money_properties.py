from hypothesis import given, strategies as st

from money import allocate, format_cents

_ratios = st.lists(
    st.integers(min_value=0, max_value=10_000), min_size=1, max_size=12
).filter(lambda rs: sum(rs) > 0)


@given(total=st.integers(min_value=1, max_value=10**12), ratios=_ratios)
def test_allocate_preserves_total(total, ratios):
    assert sum(allocate(total, ratios)) == total


@given(total=st.integers(min_value=1, max_value=10**12), ratios=_ratios)
def test_allocate_no_negative_and_zero_weight_gets_nothing(total, ratios):
    parts = allocate(total, ratios)
    assert all(p >= 0 for p in parts)
    for ratio, part in zip(ratios, parts):
        if ratio == 0:
            assert part == 0


@given(cents=st.integers(min_value=-(10**15), max_value=10**15))
def test_format_cents_roundtrips_to_exact_cents(cents):
    text = format_cents(cents, symbol="")
    sign = -1 if text.startswith("-") else 1
    whole, fraction = text.lstrip("-").split(".")
    assert sign * (int(whole) * 100 + int(fraction)) == cents
