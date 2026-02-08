"""Test that Python version matches pyproject.toml requires-python."""

import sys
import unittest


class PythonVersionTest(unittest.TestCase):
    def test_python_version_from_pyproject(self):
        """Verify we're running Python 3.11.7 as specified in pyproject.toml."""
        version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
        self.assertEqual(
            version,
            "3.11.7",
            f"Expected Python 3.11.7 from pyproject.toml, got {version}",
        )


if __name__ == "__main__":
    unittest.main()
