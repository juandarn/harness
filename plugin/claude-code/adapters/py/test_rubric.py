import ast

from rubric import complexity, is_test, main, py_files


def test_complexity_counts_branches():
    tree = ast.parse("def f(x):\n    if x:\n        return 1\n    return 0\n")
    assert complexity(tree.body[0]) == 2


def test_complexity_base_is_one():
    tree = ast.parse("def f():\n    return 1\n")
    assert complexity(tree.body[0]) == 1


def test_is_test_detection():
    assert is_test("test_foo.py")
    assert is_test("foo_test.py")
    assert not is_test("foo.py")


def test_py_files_lists_python(tmp_path):
    (tmp_path / "a.py").write_text("x = 1\n")
    (tmp_path / "b.txt").write_text("no\n")
    found = py_files(str(tmp_path))
    assert any(p.endswith("a.py") for p in found)
    assert not any(p.endswith("b.txt") for p in found)


def test_main_is_entrypoint():
    assert callable(main)
