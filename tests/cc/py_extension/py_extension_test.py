import os
import unittest

from elftools.elf.dynamic import DynamicSection
from elftools.elf.elffile import ELFFile

from python.runfiles import runfiles


class PyExtensionTest(unittest.TestCase):
    def test_inspect_elf(self):
        r = runfiles.Create()
        ext_path = r.Rlocation("rules_python/tests/cc/py_extension/ext_shared.so")
        self.assertTrue(
            os.path.exists(ext_path), f"Could not find ext_shared.so at {ext_path}"
        )

        with open(ext_path, "rb") as f:
            elf = ELFFile(f)

            # Check for DT_NEEDED entry for the dynamic library
            dynamic_section = elf.get_section_by_name(".dynamic")
            self.assertIsNotNone(dynamic_section)
            self.assertTrue(isinstance(dynamic_section, DynamicSection))

            needed_libs = [
                tag.needed
                for tag in dynamic_section.iter_tags()
                if tag.entry.d_tag == "DT_NEEDED"
            ]
            self.assertIn("libdyn_dep_a.so", needed_libs)

            # Check for the PyInit symbol
            dynsym_section = elf.get_section_by_name(".dynsym")
            self.assertIsNotNone(dynsym_section)

            symbols = [s.name for s in dynsym_section.iter_symbols()]
            self.assertIn("PyInit_ext_shared", symbols)


if __name__ == "__main__":
    unittest.main()
