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

        ##resource_path = os.path.join("_main", "tests", "cc", "current_py_cc_headers", "bin_abi3.dll")

        ##resource_path = r"_main\tests\cc\current_py_cc_headers\bin_abi3.dll"
        dll_dir = pathlib.Path(rf.Rlocation("_main/tests/cc/current_py_cc_headers"))
        dll_paths = list(dll_dir.glob("*.dll"))

        if not dll_paths:
            self.fail(f"No *.dll found in {dll_dir}")
        if len(dll_paths) > 1:
            self.fail(f"Multiple dlls found, expected one: {dll_paths}")

        dll_path = dll_paths[0]

        print("=== pl :", dll_path, os.path.exists(dll_path))
        rfp = rf.Rlocation("_main\\tests\\cc\\current_py_cc_headers\\bin_abi3.dll")
        print("=== rf1:", rfp, os.path.exists(rfp))
        pe = pefile.PE(rfp) # rf1
        rfp = rf.Rlocation("_main/tests/cc/current_py_cc_headers/bin_abi3.dll")
        print("=== rf2:", rfp, os.path.exists(rfp))
        pe = pefile.PE(rfp) # rf2

        pe = pefile.PE(rfp)
        if not hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
            self.fail("No import directory found.")

        imported_dlls = [
            entry.dll.decode("utf-8").lower() for entry in pe.DIRECTORY_ENTRY_IMPORT
        ]
        python_dlls = [dll for dll in imported_dlls if dll.startswith("python3")]
        self.assertEqual(python_dlls, ["python3.dll"])

        self.fail("done")


if __name__ == "__main__":
    unittest.main()
