"""Test that compile_pip_requirements works with PYTHON_VERSION from pyproject.toml."""

import sys
import unittest


class CompileRequirementsTest(unittest.TestCase):
    def test_python_version_matches_pyproject(self):
        """Verify we're using the Python version from pyproject.toml."""
        version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
        self.assertEqual(
            version,
            "3.11.7",
            f"Expected Python 3.11.7 from pyproject.toml, got {version}",
        )

    def test_requirements_target_exists(self):
        """
        This test just needs to run successfully.
        The fact that it runs means compile_pip_requirements worked,
        which means PYTHON_VERSION was successfully loaded from the repo.
        """
        self.assertTrue(True)


if __name__ == "__main__":
    unittest.main()
