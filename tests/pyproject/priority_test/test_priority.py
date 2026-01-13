"""Test that pyproject.toml takes priority over .python-version."""

import sys
import unittest


class PriorityTest(unittest.TestCase):
    def test_pyproject_wins_over_python_version_file(self):
        """
        Verify pyproject.toml (3.11.7) takes priority over .python-version (3.12.0).
        """
        version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
        self.assertEqual(
            version,
            "3.11.7",
            "pyproject.toml should take priority over .python-version file",
        )


if __name__ == "__main__":
    unittest.main()
