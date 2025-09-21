
import os.path
import sys
import pefile
import unittest
import pathlib

from python.runfiles import runfiles

class CheckLinkageTest(unittest.TestCase):
    def test_linkage(self):
        rf = runfiles.Create()
        d = rf.Rlocation("_main/tests/cc/current_py_cc_headers")
        d = pathlib.Path(d)
        for f in d.glob("*.dll"):
            print(f)

        d = rf.Rlocation("_main/tests/cc/current_py_cc_headers")
        print(f"[*] Analyzing dependencies for: {file_path}\n")

        try:
            # Parse the PE file
            pe = pefile.PE(file_path)

            if not hasattr(pe, 'DIRECTORY_ENTRY_IMPORT'):
                print("[!] No import directory found. The file may not have dependencies or is packed.")
                raise Exception("no deps?")

            print("Imported DLLs:")

            # Iterate over the import directory entries
            # Each 'entry' corresponds to one imported DLL
            for entry in pe.DIRECTORY_ENTRY_IMPORT:
                # entry.dll is a bytes string, so we decode it to utf-8
                dll_name = entry.dll.decode('utf-8')
                print(f"  - {dll_name}")

        except pefile.PEFormatError as e:
            print(f"Error: Not a valid PE file (DLL/EXE). \nDetails: {e}")
        except Exception as e:
            print(f"An unexpected error occurred: {e}")

        raise Exception("done")

if __name__ == "__main__":
    unittest.main()
