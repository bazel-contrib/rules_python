import unittest

from tests.cc.py_extension import ext_pkg_test


class PyExtensionPkgTest(unittest.TestCase):

    def test_import_via_package(self):
        self.assertEqual(ext_pkg_test.get_magic_number(), 42)

    def test_direct_import(self):
        with self.assertRaises(ModuleNotFoundError):
            import ext_pkg_test  # buildifier: disable=g-import-not-at-top # noqa: F401


if __name__ == "__main__":
    unittest.main()
