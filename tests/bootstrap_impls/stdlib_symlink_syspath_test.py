"""Tests that stdlib entries in sys.path point to runfiles locations.

Verifies stdlib is not added from the underlying repository location.
"""

from __future__ import annotations

import os
import pathlib
import re
import sys

from python.runfiles import runfiles


def _is_stdlib_path(path_str: str) -> bool:
    norm = path_str.replace("\\", "/").rstrip("/")
    base = norm.split("/")[-1].lower()
    if base.endswith("-packages"):
        return False
    if re.match(r"^python\d*\.zip$", base):
        return True
    if base in ("lib-dynload", "dlls", "lib"):
        return True
    if re.match(r"^python3\.\d+$", base):
        return True
    return False


def test_stdlib_sys_path_in_runfiles() -> None:
    rf = runfiles.CreateOrRaise()
    runfiles_root = rf.root()

    stdlib_paths = [p for p in sys.path if _is_stdlib_path(p)]
    assert stdlib_paths, (
        "Expected to find at least one stdlib path in sys.path:\n" + "\n".join(sys.path)
    )

    norm_root = pathlib.Path(os.path.normcase(runfiles_root))
    violations = []
    for p in stdlib_paths:
        norm_p = pathlib.Path(os.path.normcase(p))
        if not norm_p.is_relative_to(norm_root):
            violations.append(p)

    assert not violations, (
        "Expected stdlib sys.path entries to be located within "
        f"runfiles tree ({runfiles_root}), but got underlying "
        "repository locations:\n"
        + "\n".join(f"  {v}" for v in violations)
        + "\nFull sys.path:\n"
        + "\n".join(f"  {p}" for p in sys.path)
    )
