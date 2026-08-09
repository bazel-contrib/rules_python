import os
import sys
import unittest

import ext_shared  # pyrefly: ignore[missing-import]
from elftools.elf.dynamic import DynamicSection
from elftools.elf.elffile import ELFFile


class PyExtensionTest(unittest.TestCase):
    @unittest.skipIf(
        sys.platform != "linux", "ELF inspection is only supported on Linux"
    )
    def test_inspect_elf(self):
        ext_path = ext_shared.__file__
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
                tag.needed  # pyrefly: ignore[missing-attribute]
                for tag in dynamic_section.iter_tags()
                if tag.entry.d_tag == "DT_NEEDED"  # pyrefly: ignore[missing-attribute]
            ]
            self.assertIn("libadd_one_shared.so", needed_libs)

            # Check for the PyInit symbol
            dynsym_section = elf.get_section_by_name(".dynsym")
            self.assertIsNotNone(dynsym_section)

            symbols = [s.name for s in dynsym_section.iter_symbols()]
            self.assertIn("PyInit_ext_shared", symbols)

    def test_import_and_call(self):
        self.assertEqual(ext_shared.do_alpha(), 43)


if __name__ == "__main__":
    unittest.main()
