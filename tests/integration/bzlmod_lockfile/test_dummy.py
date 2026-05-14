"""
Verify that a dependency added using the pip extension can be imported.
See MODULE.bazel.
"""

import unittest

import six


class TestDummy(unittest.TestCase):
    def test_import(self):
        self.assertTrue(hasattr(six, "PY3"))


if __name__ == "__main__":
    unittest.main()
