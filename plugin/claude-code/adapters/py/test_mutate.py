from mutate import main, mutants, run_tests, score_mutants


def test_mutants_generates_for_operators():
    ops = {(old, new) for _, old, new, _ in mutants("x = a + b\n")}
    assert ("+", "-") in ops


def test_mutants_none_for_plain_line():
    assert mutants("return value\n") == []


def test_mutant_body_differs_from_source():
    src = "x = a + b\n"
    _, _, _, body = mutants(src)[0]
    assert body != src
    assert "a - b" in body


def test_helpers_are_entrypoints():
    assert callable(run_tests)
    assert callable(score_mutants)
    assert callable(main)
