from hypothesis import given, strategies as st

from money import allocate

_ratios = st.lists(
    st.integers(min_value=0, max_value=1000), min_size=1, max_size=10
).filter(lambda rs: sum(rs) > 0)


@given(
    total=st.integers(min_value=1, max_value=10**9),
    ratios=_ratios,
    k=st.integers(min_value=1, max_value=1000),
)
def test_allocate_is_scale_invariant(total, ratios, k):
    assert allocate(total, ratios) == allocate(total, [k * r for r in ratios])
