"""Tests for py_wheel_library post_install_patches, py_wheel_transform, py_wheel_extract_files, and precompile."""

from __future__ import annotations

import importlib
import importlib.metadata
import importlib.util
import os
import pathlib
import sys
import unittest


class PyWheelLibraryTest(unittest.TestCase):
    def test_post_install_patch_and_transform(self):
        sys.dont_write_bytecode = True
        demo_pkg = importlib.import_module("demo_pkg")
        expect_omit = os.environ.get("EXPECT_OMIT_SOURCE") == "1"
        if not expect_omit:
            self.assertEqual(demo_pkg.VALUE, "patched_in_action")
        self.assertEqual(demo_pkg.TRANSFORMED, "custom_marker")
        self.assertEqual(importlib.metadata.version("demo-pkg"), "1.2.3")
        expect_venv = os.environ.get("EXPECT_VENV_SITE_PACKAGES") == "1"
        pkg_file = pathlib.Path(demo_pkg.__file__ or "")
        self.assertEqual(
            pkg_file.is_relative_to(sys.prefix),
            expect_venv,
        )

        if expect_omit:
            self.assertEqual(pkg_file.suffix, ".pyc")
            self.assertFalse(pkg_file.with_suffix(".py").exists())
        else:
            # Verify precompile flag-driven behavior (__pycache__/*.pyc presence).
            pyc_files = list((pkg_file.parent / "__pycache__").glob("*.pyc"))
            if os.environ.get("EXPECT_PRECOMPILE") == "1":
                self.assertTrue(
                    pyc_files,
                    f"Expected precompiled .pyc in {pkg_file.parent / '__pycache__'}",
                )
                spec = demo_pkg.__spec__
                assert spec is not None
                cached = pathlib.Path(spec.cached or "")
                self.assertTrue(cached.is_file(), f"Missing cached pyc: {cached}")
                self.assertEqual(cached.read_bytes()[:4], importlib.util.MAGIC_NUMBER)
                if expect_venv:
                    self.assertTrue(cached.is_symlink(), f"Expected symlink: {cached}")
            else:
                self.assertEqual(pyc_files, [])

        # Verify an uncompilable top-level module raises SyntaxError on import
        # and never leaves dangling symlinks in the venv site-packages tree.
        with self.assertRaises(SyntaxError):
            importlib.import_module("bad_top_mod")
        if expect_venv:
            site_packages_dir = pkg_file.parent.parent
            for entry in site_packages_dir.rglob("*"):
                if entry.is_symlink():
                    self.assertTrue(
                        entry.exists(),
                        f"Dangling venv symlink in site-packages: {entry} -> {os.readlink(entry)}",
                    )

        # Verify py_wheel_extract_files + copy_files reflects post_install_patch
        # and copy_executables preserves executable bit.
        copied_init = pathlib.Path(os.environ["COPIED_PATCHED_INIT"])
        self.assertTrue(copied_init.is_file())
        copied_text = copied_init.read_text(encoding="utf-8")
        self.assertIn('VALUE = "patched_in_action"', copied_text)
        self.assertIn('TRANSFORMED = "custom_marker"', copied_text)

        copied_exec = pathlib.Path(os.environ["COPIED_EXEC_SCRIPT"])
        self.assertTrue(copied_exec.is_file())
        self.assertTrue(os.access(copied_exec, os.X_OK))

    def test_sdist_wheel_and_pre_build_patch(self):
        sys.dont_write_bytecode = True
        sdist_demo = importlib.import_module("sdist_demo")
        self.assertEqual(sdist_demo.GREETING, "patched_before_build")
        self.assertEqual(importlib.metadata.version("sdist-demo"), "0.5.0")


if __name__ == "__main__":
    unittest.main()
