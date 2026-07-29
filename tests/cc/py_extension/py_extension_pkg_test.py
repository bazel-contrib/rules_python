import os
import sys
import unittest

if sys.platform == "win32":
    for path in sys.path:
        if os.path.isdir(path):
            try:
                os.add_dll_directory(path)
            except Exception:
                pass

from tests.cc.py_extension import ext_pkg_test


class PyExtensionPkgTest(unittest.TestCase):
    def test_import_via_package(self):
        self.assertEqual(ext_pkg_test.get_magic_number(), 42)

    def test_direct_import(self):
        with self.assertRaises(ModuleNotFoundError):
            import ext_pkg_test  # buildifier: disable=g-import-not-at-top # noqa: F401


if __name__ == "__main__":
    unittest.main()
