# Ported from rigor-harness gates/test_run_gates.py, same directory layout
# as run_gates.py so the import resolves without path changes.
import os

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


def test_harness_root_defaults_to_the_plugin_root():
    ok, out = run_gate({"run": "echo $HARNESS_ROOT"}, ".")
    assert ok
    assert os.path.isfile(os.path.join(out, "gates", "run_gates.py"))


def test_plugin_root_is_exported_for_gate_commands():
    ok, out = run_gate({"run": "echo ${CLAUDE_PLUGIN_ROOT}"}, ".")
    assert ok
    assert os.path.isdir(os.path.join(out, "gates"))
