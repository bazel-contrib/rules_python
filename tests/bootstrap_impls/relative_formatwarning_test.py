import os
import string
import sys
import unittest
import warnings


class RelativeFormatwarningTest(unittest.TestCase):
    def format(self, filename):
        return warnings.formatwarning("msg", UserWarning, filename, 1)

    def test_formatwarning_is_wrapped(self):
        self.assertEqual(warnings.formatwarning.__name__, "relpath_formatwarning")

    def test_path_within_cwd_is_relative(self):
        filename = os.path.join(os.getcwd(), "pkg", "mod.py")
        expected = os.path.join("pkg", "mod.py")
        self.assertTrue(self.format(filename).startswith(expected + ":1: "))

    def test_path_outside_cwd_is_absolute(self):
        # e.g. a warning from the stdlib
        filename = os.path.join(os.path.dirname(os.getcwd()), "other", "mod.py")
        self.assertTrue(self.format(filename).startswith(filename + ":1: "))

    def test_relative_path_is_unchanged(self):
        filename = os.path.join("pkg", "mod.py")
        self.assertTrue(self.format(filename).startswith(filename + ":1: "))

    def test_warn_from_file_within_cwd(self):
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            warnings.warn("msg")
        warning = caught[0]
        formatted = warnings.formatwarning(
            warning.message, warning.category, warning.filename, warning.lineno
        )
        # The test runs from the runfiles directory that contains this file.
        expected = os.path.relpath(warning.filename, os.getcwd())
        self.assertFalse(expected.startswith(".."), expected)
        self.assertTrue(formatted.startswith(expected + ":"), formatted)

    @unittest.skipUnless(sys.platform == "win32", "drive letters are Windows-only")
    def test_path_on_other_drive_is_absolute(self):
        cwd_drive = os.path.splitdrive(os.getcwd())[0].upper()
        drive = next(
            d + ":" for d in reversed(string.ascii_uppercase) if d + ":" != cwd_drive
        )
        filename = drive + "\\other\\mod.py"
        # This raised ValueError, because relpath() can't cross drives.
        self.assertTrue(self.format(filename).startswith(filename + ":1: "))


if __name__ == "__main__":
    unittest.main()
