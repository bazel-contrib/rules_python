from __future__ import annotations

import importlib
import importlib.metadata
import os
import subprocess
import sys
import unittest
from pathlib import Path


class TreeConflictsTest(unittest.TestCase):
    def setUp(self) -> None:
        super().setUp()
        self.assertNotEqual(
            sys.prefix, sys.base_prefix, "Expected to run inside a venv"
        )
        self.venv = Path(sys.prefix)
        self.order = os.environ["EXPECTED_ORDER"]
        self.precompile = os.environ.get("EXPECTED_PRECOMPILE", "")

    def _get_script_path(self, name: str) -> Path:
        if sys.platform != "win32":
            return self.venv / "bin" / name
        bin_dir = self.venv / "Scripts"
        pathexts = os.environ.get("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";")
        for ext in [""] + [e.lower() for e in pathexts]:
            candidate = bin_dir / f"{name}{ext}"
            if candidate.exists():
                return candidate
        return bin_dir / name

    def _assert_in_venv(self, mod_file: str | None, mod_name: str) -> Path:
        self.assertIsNotNone(mod_file, f"Expected __file__ on {mod_name}")
        assert mod_file is not None  # type assert
        actual = str(Path(mod_file)).lower() if os.name == "nt" else mod_file
        prefix = str(self.venv).lower() if os.name == "nt" else str(self.venv)
        self.assertTrue(
            actual.startswith(prefix),
            f"{mod_name} ({mod_file}) was not loaded from venv ({self.venv})",
        )
        return Path(mod_file)

    def test_merged_packages_and_conflict_priority(self) -> None:
        foo = importlib.import_module("foo")
        foo_a = importlib.import_module("foo.a")
        foo_b = importlib.import_module("foo.plugins.b")
        foo_c = importlib.import_module("foo.plugins.c")
        foo_shared = importlib.import_module("foo.plugins.shared")
        gns_alpha = importlib.import_module("gns.alpha")
        gns_beta = importlib.import_module("gns.beta")
        gns_gamma = importlib.import_module("gns.gamma")
        gns_helper = importlib.import_module("gns.libs.helper")
        pk = importlib.import_module("pk")
        pk_x = importlib.import_module("pk.x")
        pk_y = importlib.import_module("pk.y")
        pk_z = importlib.import_module("pk.z")
        bar = importlib.import_module("bar")
        bar_m = importlib.import_module("bar.m")
        bar_e = importlib.import_module("bar.ext.e")

        self.assertEqual(foo.WHO, "foo-from-a")
        self.assertEqual(foo_a.WHO, "a")
        self.assertEqual(foo_b.WHO, "b")
        self.assertEqual(foo_c.WHO, "c")
        # Shortest venv_path ("foo" vs "foo/plugins") expands first regardless of dep order.
        self.assertEqual(foo_shared.WHO, "A")

        self.assertEqual(gns_alpha.WHO, "alpha")
        self.assertEqual(gns_beta.WHO, "beta")
        self.assertEqual(gns_gamma.WHO, "gamma")
        self.assertEqual(gns_helper.WHO, "helper")

        # Equal venv_path ("pk/__init__.py"): first in dep order wins.
        expected_pk_origin = "A" if self.order == "ab" else "B"
        self.assertEqual(pk.ORIGIN, expected_pk_origin)
        self.assertEqual(pk_x.WHO, "x")
        self.assertEqual(pk_y.WHO, "y")
        self.assertEqual(pk_z.WHO, "z")

        self.assertEqual(bar.WHO, "bar-fp2")
        self.assertEqual(bar_m.WHO, "m")
        self.assertEqual(bar_e.WHO, "e")

        for mod in (
            foo,
            foo_a,
            foo_b,
            foo_c,
            foo_shared,
            gns_alpha,
            gns_beta,
            gns_gamma,
            gns_helper,
            pk,
            pk_x,
            pk_y,
            pk_z,
            bar,
            bar_m,
            bar_e,
        ):
            self._assert_in_venv(mod.__file__, mod.__name__)

        libs_dir = self._assert_in_venv(gns_helper.__file__, gns_helper.__name__).parent
        self.assertFalse(
            libs_dir.is_symlink(), "gns/libs must be a real merged directory"
        )
        libs_entries = set(os.listdir(libs_dir))
        self.assertIn("libdummy_a.so", libs_entries)
        self.assertIn("libdummy_b.so", libs_entries)
        self.assertTrue(
            "helper.py" in libs_entries or "helper.pyc" in libs_entries,
            f"Expected helper module in {libs_entries}",
        )

        self.assertEqual(importlib.metadata.version("tree-conflict-a"), "1.0")
        self.assertEqual(importlib.metadata.version("tree-conflict-b"), "1.0")

        if self.precompile == "enabled":
            foo_dir = self._assert_in_venv(foo.__file__, foo.__name__).parent
            has_pyc = (foo_dir / "a.pyc").exists() or (
                (foo_dir / "__pycache__").is_dir()
                and any(
                    name.startswith("a.") and name.endswith(".pyc")
                    for name in os.listdir(foo_dir / "__pycache__")
                )
            )
            self.assertTrue(
                has_pyc, f"Expected precompiled bytecode for foo.a in {foo_dir}"
            )

    def test_bin_scripts_and_conflict_priority(self) -> None:
        expected_tool = "tool-A" if self.order == "ab" else "tool-B"
        for script_name, expected_stdout in (
            ("tc_tool", expected_tool),
            ("tc_a_only", "a-only"),
            ("tc_b_only", "b-only"),
        ):
            script_path = self._get_script_path(script_name)
            self.assertTrue(script_path.exists(), f"Missing script {script_path}")
            proc = subprocess.run(
                [str(script_path)],
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertEqual(proc.stdout.strip(), expected_stdout)


if __name__ == "__main__":
    unittest.main()
