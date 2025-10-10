import os
import unittest

from elftools.elf.elffile import ELFFile
from macholib.MachO import MachO


class SharedLibLoadingTest(unittest.TestCase):
    def test_shared_library_linking(self):
        import ext_with_libs.adder

        # Check that the module was loaded from the venv.
        self.assertIn(".venv/", ext_with_libs.adder.__file__)

        adder_path = os.path.realpath(ext_with_libs.adder.__file__)

        with open(adder_path, "rb") as f:
            magic_bytes = f.read(4)

        if magic_bytes == b"\x7fELF":
            self._assert_elf_linking(adder_path)
        elif magic_bytes in (b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe"):
            self._assert_macho_linking(adder_path)
        else:
            self.fail(f"Unsupported file format for adder: magic bytes {magic_bytes!r}")

        # Check the function works regardless of format.
        self.assertEqual(ext_with_libs.adder.do_add(), 2)

    def _assert_elf_linking(self, path):
        """Asserts dynamic linking properties for an ELF file."""
        with open(path, "rb") as f:
            elf = ELFFile(f)

            # Check that the adder module depends on the increment library.
            needed = []
            dynamic_section = elf.get_section_by_name(".dynamic")
            self.assertIsNotNone(dynamic_section)
            for tag in dynamic_section.iter_tags("DT_NEEDED"):
                needed.append(tag.needed)
            self.assertIn("libincrement.so", needed)

            # Check that the 'increment' symbol is undefined.
            dynsym_section = elf.get_section_by_name(".dynsym")
            self.assertIsNotNone(dynsym_section)
            undefined_symbols = [
                s.name
                for s in dynsym_section.iter_symbols()
                if s.entry["st_shndx"] == "SHN_UNDEF"
            ]
            self.assertIn("increment", undefined_symbols)

    def _assert_macho_linking(self, path):
        """Asserts dynamic linking properties for a Mach-O file."""
        macho = MachO(path)

        # Check dependency on the increment library.
        loaded_dylibs = [
            cmd.name
            for header in macho.headers
            for cmd_load, cmd, data in header.commands
            if cmd_load == "LC_LOAD_DYLIB"
        ]
        self.assertIn("@rpath/libincrement.dylib", loaded_dylibs)

        # Check that the 'increment' symbol is undefined.
        self.assertIsNotNone(macho.symtab)
        undefined_symbols = [
            s.n_name.decode()
            for s in macho.symtab.nlists
            if s.n_type & 0x01 and s.n_sect == 0  # N_EXT and NO_SECT
        ]
        self.assertIn("_increment", undefined_symbols)


if __name__ == "__main__":
    unittest.main()
