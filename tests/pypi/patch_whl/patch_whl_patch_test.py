"""Test that wheel patching works end-to-end."""

import unittest

import pkg


class PatchWhlTest(unittest.TestCase):
    def test_patched(self):
        self.assertEqual(pkg.PATCHED, True)

    def test_data_unchanged(self):
        self.assertEqual(pkg.DATA, "hello")


if __name__ == "__main__":
    unittest.main()
