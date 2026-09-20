def _validate(total, ratios):
    if isinstance(total, bool) or not isinstance(total, int) or total <= 0:
        raise ValueError("total must be a positive integer")
    if not ratios:
        raise ValueError("ratios must be non-empty")
    if any(isinstance(r, bool) or not isinstance(r, int) or r < 0 for r in ratios):
        raise ValueError("ratios must be non-negative integers")
    if sum(ratios) == 0:
        raise ValueError("ratios must not all be zero")


def allocate(total, ratios):
    _validate(total, ratios)
    denom = sum(ratios)
    parts = [total * r // denom for r in ratios]
    recipients = [i for i, r in enumerate(ratios) if r > 0]
    undistributed = total - sum(parts)
    for k in range(undistributed):
        parts[recipients[k % len(recipients)]] += 1
    return parts


def format_cents(cents, symbol="$"):
    if isinstance(cents, bool) or not isinstance(cents, int):
        raise ValueError("cents must be an integer")
    sign = "-" if cents < 0 else ""
    whole, fraction = divmod(abs(cents), 100)
    return f"{sign}{symbol}{whole}.{fraction:02d}"
