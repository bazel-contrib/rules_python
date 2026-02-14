"""Test that py_wheel produces correct wheel contents with many deps.

Verifies that the Args.add_all(map_each=...) approach used to write the
input file list produces a wheel with the expected files.
"""

import os
import unittest
import zipfile

from python.runfiles import runfiles

_WHEEL_NAME = "verify_wheel-0.0.1-py3-none-any.whl"
_EXPECTED_MODULE_COUNT = 100


class PyWheelContentsTest(unittest.TestCase):

    def setUp(self):
        self.rf = runfiles.Create()
        whl_path = self.rf.Rlocation(
            os.path.join("rules_python", "tests", "py_wheel_performance", _WHEEL_NAME)
        )
        self.assertIsNotNone(whl_path, "Could not find wheel via runfiles")
        self.assertTrue(os.path.exists(whl_path), f"Wheel not found: {whl_path}")
        self.whl_path = whl_path

    def test_verify_wheel_has_all_modules(self):
        """Verify the wheel contains exactly the expected number of .py files."""
        with zipfile.ZipFile(self.whl_path) as whl:
            py_files = [n for n in whl.namelist() if n.endswith(".py")]
            self.assertEqual(
                len(py_files),
                _EXPECTED_MODULE_COUNT,
                f"Expected {_EXPECTED_MODULE_COUNT} .py files in wheel, got {len(py_files)}",
            )

    def test_verify_wheel_file_contents(self):
        """Verify the .py files in the wheel have the expected content."""
        with zipfile.ZipFile(self.whl_path) as whl:
            py_files = sorted(n for n in whl.namelist() if n.endswith(".py"))
            self.assertTrue(py_files, "No .py files found in wheel")
            first = whl.read(py_files[0]).decode("utf-8")
            self.assertIn("Generated module", first)
            self.assertIn("VALUE =", first)

    def test_verify_wheel_metadata(self):
        """Verify the wheel has proper metadata files."""
        with zipfile.ZipFile(self.whl_path) as whl:
            names = whl.namelist()
            metadata_files = [
                n for n in names if "METADATA" in n or "WHEEL" in n or "RECORD" in n
            ]
            self.assertTrue(
                len(metadata_files) >= 3,
                f"Expected METADATA, WHEEL, RECORD files; got {metadata_files}",
            )

            metadata_path = [n for n in names if n.endswith("METADATA")][0]
            metadata = whl.read(metadata_path).decode("utf-8")
            self.assertIn("Name: verify_wheel", metadata)
            self.assertIn("Version: 0.0.1", metadata)


if __name__ == "__main__":
    unittest.main()
