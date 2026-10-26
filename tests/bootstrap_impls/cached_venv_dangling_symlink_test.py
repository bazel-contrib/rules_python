"""Regression test for dangling runtime package links in persistent venvs."""

from __future__ import annotations

import os
import pathlib
import sys
import tempfile
import unittest

from python.runfiles import runfiles


def _load_bootstrap() -> dict:
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


class CachedVenvDanglingSymlinkTest(unittest.TestCase):
    def test_replaces_dangling_package_link_before_creating_child_link(self) -> None:
        bootstrap = _load_bootstrap()
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            runfiles = root / "runfiles"
            old_package = runfiles / "old/annotated_types"
            old_package.mkdir(parents=True)
            (old_package / "__init__.py").touch()
            bootstrap.update(
                EXTRACT_ROOT=str(root / "cache"),
                PYTHON_BINARY="_main/_process.venv/Scripts/python.exe",
                PYTHON_BINARY_ACTUAL=sys.executable,
                RESOLVE_PYTHON_BINARY_AT_RUNTIME=False,
                RUNTIME_VENV_SYMLINKS={
                    "Lib/site-packages/annotated_types": "old/annotated_types",
                },
            )

            bootstrap["_create_venv"](str(runfiles), [])
            old_package.rename(root / "retired-package")

            new_package = runfiles / "new/annotated_types"
            new_package.mkdir(parents=True)
            (new_package / "__init__.py").touch()
            bootstrap["RUNTIME_VENV_SYMLINKS"] = {
                "Lib/site-packages/annotated_types/__init__.py": "new/annotated_types/__init__.py",
            }

            bootstrap["_create_venv"](str(runfiles), [])

            package = (
                root / "cache/_main/_process.venv/Lib/site-packages/annotated_types"
            )
            package_init = package / "__init__.py"
            self.assertTrue(package.is_dir())
            self.assertFalse(package.is_symlink())
            self.assertTrue(package_init.is_symlink())
            self.assertTrue(os.path.samefile(package_init, new_package / "__init__.py"))


if __name__ == "__main__":
    unittest.main()
