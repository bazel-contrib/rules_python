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
        p1 = rf.Rlocation("rules_python/tests/cc/current_py_cc_headers/bin_abi3.dll")
        print("=== p1:", os.path.exists(p1), p1)
        p2 = rf.Rlocation("tests/cc/current_py_cc_headers/bin_abi3.dll")
        print("=== p2:", os.path.exists(p2), p2)

        dll_path = rf.Rlocation("rules_python/tests/cc/current_py_cc_headers/bin_abi3.dll")
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
