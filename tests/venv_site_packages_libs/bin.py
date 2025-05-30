import importlib
import os
import sys
import unittest
from pathlib import Path


class VenvSitePackagesLibraryTest(unittest.TestCase):
    def setUp(self):
        super().setUp()
        if sys.prefix == sys.base_prefix:
            raise AssertionError("Not running under a venv")
        self.venv = sys.prefix

    def assert_imported_from_venv(self, module_name):
        module = importlib.import_module(module_name)
        self.assertEqual(module.__name__, module_name)
        self.assertTrue(
            module.__file__.startswith(self.venv),
            f"\n{module_name} was imported, but not from the venv.\n"
            + f"venv  : {self.venv}\n"
            + f"actual: {module.__file__}",
        )

    def test_imported_from_venv(self):
        self.assert_imported_from_venv("nspkg.subnspkg.alpha")
        self.assert_imported_from_venv("nspkg.subnspkg.beta")
        self.assert_imported_from_venv("nspkg.subnspkg.gamma")
        self.assert_imported_from_venv("nspkg.subnspkg.delta")
        self.assert_imported_from_venv("single_file")
        self.assert_imported_from_venv("simple")

    def test_distinfo_is_overriden(self):
        self.assert_imported_from_venv("simple")
        module = importlib.import_module("simple")
        module_path = Path(module.__file__)
        site_packages = module_path.parent.parent

        dist_info_dirs = [p.name for p in site_packages.glob("*.dist-info")]

        self.assertEqual(
            "2.0.0",
            module.__version__,
        )
        self.assertEqual(
            ["simple-2.0.0.dist-info"],
            dist_info_dirs,
        )


if __name__ == "__main__":
    unittest.main()
