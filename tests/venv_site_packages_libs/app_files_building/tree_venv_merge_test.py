"""Runtime test verifying merged TreeArtifact-backed venv site-packages."""

from __future__ import annotations

import importlib
import os
import sys
import unittest
from pathlib import Path


class TreeVenvMergeTest(unittest.TestCase):
    def _assert_in_venv(self, mod_file: str | None, mod_name: str) -> None:
        self.assertIsNotNone(mod_file, f"Expected __file__ on {mod_name}")
        assert mod_file is not None  # type assert
        actual = str(Path(mod_file)).lower() if os.name == "nt" else mod_file
        prefix = str(Path(sys.prefix)).lower() if os.name == "nt" else sys.prefix
        self.assertTrue(
            actual.startswith(prefix),
            f"{mod_name} ({mod_file}) was not loaded from venv ({sys.prefix})",
        )

    def test_imports_from_merged_tree_artifacts(self) -> None:
        self.assertNotEqual(
            sys.prefix, sys.base_prefix, "Expected to run inside a venv"
        )
        foo = importlib.import_module("foo")
        foo_a = importlib.import_module("foo.a")
        foo_b = importlib.import_module("foo.plugins.b")
        foo_shared = importlib.import_module("foo.plugins.shared")
        ns_one = importlib.import_module("pkgutil_ns.one")
        ns_two = importlib.import_module("pkgutil_ns.two")

        self.assertEqual(foo.ORIGIN, "tree_a")
        self.assertEqual(foo_a.VALUE, "from_a")
        self.assertEqual(foo_b.VALUE, "from_b")
        self.assertEqual(foo_shared.WINNER, "tree_a")
        self.assertEqual(ns_one.VALUE, 1)
        self.assertEqual(ns_two.VALUE, 2)

        for mod in (foo, foo_a, foo_b, foo_shared, ns_one, ns_two):
            self._assert_in_venv(mod.__file__, mod.__name__)


if __name__ == "__main__":
    unittest.main()
