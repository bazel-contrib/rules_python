"""Loads python_bootstrap_template.txt as a module, for testing its functions."""

from __future__ import annotations

import pathlib
import sys

from python.runfiles import runfiles


def load_bootstrap() -> dict:
    r = runfiles.Create()
    if r:
        template_path = r.Rlocation(
            "rules_python/python/private/python_bootstrap_template.txt"
        )
        assert template_path is not None
        template = pathlib.Path(template_path)
    else:
        template = (
            pathlib.Path(__file__).resolve().parents[2]
            / "python/private/python_bootstrap_template.txt"
        )
    source = template.read_text(encoding="utf-8")
    for placeholder, value in [
        ("%shebang%", "#!/usr/bin/env python3"),
        ("%stage2_bootstrap%", "unused.py"),
        ("%runtime_venv_symlinks%", ""),
    ]:
        source = source.replace(placeholder, value)

    bootstrap = {"__name__": "bootstrap_test"}
    saved_path = sys.path[:]
    try:
        exec(compile(source, str(template), "exec"), bootstrap)
    finally:
        sys.path[:] = saved_path
    return bootstrap
