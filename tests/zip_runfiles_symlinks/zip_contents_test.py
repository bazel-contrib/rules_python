import os
import unittest
import zipfile

from python.runfiles import runfiles


class ZipContentsTest(unittest.TestCase):
    def setUp(self):
        super().setUp()
        rf = runfiles.Create()
        zip_rlocation = os.environ["ZIP_RLOCATION"]
        zip_path = rf.Rlocation(zip_rlocation)
        self.assertIsNotNone(zip_path, msg=f"Could not find zip at {zip_rlocation}")
        with zipfile.ZipFile(zip_path) as zf:
            self.names = set(zf.namelist())

    def assertInZip(self, expected):
        self.assertIn(
            expected,
            self.names,
            msg=f"Expected {expected!r} in zip; got: {sorted(self.names)}",
        )

    def test_runfiles_symlink_is_present(self):
        self.assertInZip("runfiles/_main/symlink_data/via_symlink.txt")

    def test_runfiles_root_symlink_is_present(self):
        self.assertInZip("runfiles/via_root_symlink.txt")


if __name__ == "__main__":
    unittest.main()
