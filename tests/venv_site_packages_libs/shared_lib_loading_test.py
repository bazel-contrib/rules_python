import unittest

from elftools.elf.elffile import ELFFile


class SharedLibLoadingTest(unittest.TestCase):
    def test_ext_loads_and_resolves(self):
        import ext_with_libs.adder

        # Check that the module was loaded from the venv.
        self.assertIn(".venv/", ext_with_libs.adder.__file__)

        with open(ext_with_libs.adder.__file__, "rb") as f:
            elf = ELFFile(f)

            # Check that the adder module depends on the increment library.
            needed = []
            dynamic_section = elf.get_section_by_name(".dynamic")
            if dynamic_section:
                for tag in dynamic_section.iter_tags("DT_NEEDED"):
                    needed.append(tag.needed)
            self.assertIn("libincrement.so", needed)

            # Check that the 'increment' symbol is undefined in the adder module,
            # as it's dynamically linked.
            is_increment_undefined = False
            dynsym_section = elf.get_section_by_name(".dynsym")
            undefined_dynamic_symbols = []
            if dynsym_section:
                for symbol in dynsym_section.iter_symbols():
                    if symbol.entry["st_shndx"] == "SHN_UNDEF":
                        undefined_dynamic_symbols.append(symbol.name)
            self.assertIn("increment", undefined_dynamic_symbols)

        # Check the function.
        self.assertEqual(ext_with_libs.adder.do_add(), 2)


if __name__ == "__main__":
    unittest.main()
