import os.path
import pathlib
import sys
import unittest

import pefile

from python.runfiles import runfiles


class CheckLinkageTest(unittest.TestCase):
    @unittest.skipUnless(sys.platform.startswith("win"), "requires windows")
    def test_linkage_windows(self):
        rf = runfiles.Create()

        resource_path = os.path.join("_main", "tests", "cc", "current_py_cc_headers", "bin_abi3.dll")

        ##resource_path = r"_main\tests\cc\current_py_cc_headers\bin_abi3.dll"
        dll_path = rf.Rlocation(resource_path)
        dll_path = dll_path.replace("/", "\\")
        if not os.path.exists(dll_path):
            self.fail(f"dll at {dll_path} does not exist")

        pe = pefile.PE(dll_path)
        if not hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
            self.fail("No import directory found.")

        imported_dlls = [
            entry.dll.decode("utf-8").lower() for entry in pe.DIRECTORY_ENTRY_IMPORT
        ]
        python_dlls = [dll for dll in imported_dlls if dll.startswith("python3")]
        self.assertEqual(python_dlls, ["python3.dll"])


if __name__ == "__main__":
    unittest.main()
