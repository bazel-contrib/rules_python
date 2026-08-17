"""Tests that workflow scripts with shebangs have executable permissions."""

import stat

from python.runfiles import runfiles


def test_py_files_with_shebangs_are_executable():
    rf = runfiles.CreateOrRaise()
    workflows_dir = rf.root() / "rules_python/.github/workflows"
    py_files = list(workflows_dir.glob("*.py"))

    assert len(py_files) > 0, f"No Python files found in {workflows_dir}"

    for py_file in py_files:
        first_line = py_file.read_text(encoding="utf-8", errors="ignore").splitlines()[
            0
        ]
        if first_line.startswith("#!"):
            mode = py_file.stat().st_mode
            is_executable = bool(mode & stat.S_IXUSR)
            assert is_executable, (
                f"{py_file.name} has a shebang ('{first_line}') but does not "
                f"have executable (+x) permissions (mode: {oct(mode)})"
            )
