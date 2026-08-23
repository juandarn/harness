# Ported from rigor-harness gates/test_run_gates.py, same directory layout
# as run_gates.py so the import resolves without path changes.
from run_gates import main, run_gate


def test_run_gate_success():
    ok, _ = run_gate({"run": "true"}, ".")
    assert ok


def test_run_gate_failure():
    ok, _ = run_gate({"run": "false"}, ".")
    assert not ok


def test_run_gate_captures_output():
    ok, out = run_gate({"run": "echo hello"}, ".")
    assert ok
    assert "hello" in out


def test_main_is_entrypoint():
    assert callable(main)
