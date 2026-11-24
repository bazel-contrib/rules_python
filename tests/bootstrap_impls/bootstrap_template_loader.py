"""Loads the bootstrap templates as modules, for testing their functions."""

from __future__ import annotations

import ast
import functools
import os
import pathlib
import sys

from python.runfiles import runfiles


def _template_path(rel_path: str) -> pathlib.Path:
    r = runfiles.Create()
    if r:
        path = r.Rlocation("rules_python/" + rel_path)
        assert path is not None
        return pathlib.Path(path)
    return pathlib.Path(__file__).resolve().parents[2] / rel_path


def load_bootstrap() -> dict:
    template = _template_path("python/private/python_bootstrap_template.txt")
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


def load_functions(rel_path: str, names: list[str]) -> dict:
    """Loads some functions of a template without running the rest of it.

    Returns:
        The globals of the functions, so that tests can replace the
        functions that they call.
    """
    template = _template_path(rel_path)
    tree = ast.parse(template.read_text(encoding="utf-8"))
    functions = [
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name in names
    ]
    assert len(functions) == len(names), f"not all of {names} are in {rel_path}"
    module = {
        "__name__": "template_test",
        "cache": functools.cache,
        "os": os,
        "sys": sys,
        "IS_WINDOWS": os.name == "nt",
    }
    exec(
        compile(ast.Module(body=functions, type_ignores=[]), str(template), "exec"),
        module,
    )
    return module
