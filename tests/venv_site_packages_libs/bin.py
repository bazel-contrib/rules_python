import importlib
import os
import sys
import unittest


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


if __name__ == "__main__":
    unittest.main()
