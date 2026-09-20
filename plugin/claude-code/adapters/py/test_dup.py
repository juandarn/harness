from dup import dup_pct, main, sig_lines


def test_dup_pct_all_unique():
    assert dup_pct(["a", "b", "c"]) == 0.0


def test_dup_pct_with_repeats():
    assert dup_pct(["a", "a", "a", "b"]) == 50.0


def test_sig_lines_skips_trivial_and_imports(tmp_path):
    f = tmp_path / "m.py"
    f.write_text("import os\n\nx = 1\n")
    lines = sig_lines(str(f))
    assert "x = 1" in lines
    assert "import os" not in lines


def test_sig_lines_skips_test_files(tmp_path):
    (tmp_path / "test_m.py").write_text("y = 2\n")
    assert sig_lines(str(tmp_path)) == []


def test_main_is_entrypoint():
    assert callable(main)
