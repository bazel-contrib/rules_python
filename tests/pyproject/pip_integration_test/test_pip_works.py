"""Test that pip dependencies resolve correctly with pyproject.toml."""

import sys
import unittest


class PipIntegrationTest(unittest.TestCase):
    def test_python_version(self):
        """Verify Python version from pyproject.toml."""
        version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
        self.assertEqual(version, "3.11.7")

    def test_can_import_dependency(self):
        """Verify pip dependency was resolved."""
        import requests

        self.assertTrue(callable(requests.get))


if __name__ == "__main__":
    unittest.main()
