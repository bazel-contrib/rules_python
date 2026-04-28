"""
Verify that a dependency added using an isolated extension can be imported.
See MODULE.bazel.
"""

import six
import unittest


class TestIsolated(unittest.TestCase):
    def test_import(self):
        self.assertTrue(hasattr(six, "PY3"))


if __name__ == "__main__":
    unittest.main()
