"""Tests C-extension sdist building and determinism in py_sdist_wheel."""

from __future__ import annotations

import importlib
import importlib.metadata
import pathlib
import unittest

from python.runfiles import runfiles


class SdistCextTest(unittest.TestCase):
    def test_import_cext_and_metadata(self):
        sdist_cext = importlib.import_module("sdist_cext")
        cext_demo = importlib.import_module("cext_demo")
        self.assertEqual(sdist_cext.add_ints(19, 23), 42)
        self.assertEqual(cext_demo.add_ints(100, 200), 300)
        self.assertEqual(importlib.metadata.version("sdist-cext"), "0.1.0")

    def test_wheel_determinism_across_distinct_scratch_dirs(self):
        rf = runfiles.Create()
        assert rf is not None
        rloc_a = rf.Rlocation(
            "rules_python/tests/pypi/py_wheel_library/sdist_cext_a.whldir"
        )
        rloc_b = rf.Rlocation(
            "rules_python/tests/pypi/py_wheel_library/sdist_cext_b.whldir"
        )
        assert rloc_a is not None
        assert rloc_b is not None
        whls_a = list(pathlib.Path(rloc_a).glob("*.whl"))
        whls_b = list(pathlib.Path(rloc_b).glob("*.whl"))
        self.assertEqual(len(whls_a), 1)
        self.assertEqual(len(whls_b), 1)
        self.assertEqual(whls_a[0].name, whls_b[0].name)
        self.assertEqual(whls_a[0].read_bytes(), whls_b[0].read_bytes())


if __name__ == "__main__":
    unittest.main()
