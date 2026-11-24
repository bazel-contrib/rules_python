import os
import pathlib
import struct
import unittest

ELF_MAGIC = b"\x7fELF"
ELFCLASS64 = 2
ELFDATA2LSB = 1
EM_AARCH64 = 183


def _find_runfiles_root() -> pathlib.Path:
    runfiles_dir = os.environ.get("TEST_SRCDIR") or os.environ.get("RUNFILES_DIR")
    if not runfiles_dir:
        raise AssertionError("Neither TEST_SRCDIR nor RUNFILES_DIR is set")
    return pathlib.Path(runfiles_dir)


def _read_elf_header(path: pathlib.Path) -> tuple[bytes, int, int, int]:
    with path.open("rb") as f:
        header = f.read(20)
    magic = header[0:4]
    ei_class = header[4]
    ei_data = header[5]
    # e_machine is at offset 18 (uint16, little-endian for ELFDATA2LSB).
    (e_machine,) = struct.unpack("<H", header[18:20])
    return magic, ei_class, ei_data, e_machine


class CrossCompileTest(unittest.TestCase):
    def _assert_aarch64_so(self, pattern: str) -> None:
        root = _find_runfiles_root()
        matches = list(root.rglob(pattern))
        self.assertTrue(
            matches,
            f"Expected aarch64 extension matching {pattern!r} under {root}",
        )
        so_path = matches[0]
        magic, ei_class, ei_data, e_machine = _read_elf_header(so_path)
        self.assertEqual(magic, ELF_MAGIC, f"{so_path} is not an ELF binary")
        self.assertEqual(ei_class, ELFCLASS64, f"{so_path} is not 64-bit ELF")
        self.assertEqual(ei_data, ELFDATA2LSB, f"{so_path} is not little-endian ELF")
        self.assertEqual(
            e_machine,
            EM_AARCH64,
            f"{so_path} has e_machine={e_machine}, expected EM_AARCH64 ({EM_AARCH64})",
        )

    def test_markupsafe_aarch64_elf(self):
        self._assert_aarch64_so("_speedups.cpython-*-aarch64-linux-gnu.so")

    def test_tiny_meson_c_aarch64_elf(self):
        self._assert_aarch64_so("_tiny_c.cpython-*-aarch64-linux-gnu.so")

    def test_tiny_meson_cpp_aarch64_elf(self):
        self._assert_aarch64_so("_tiny_cpp.cpython-*-aarch64-linux-gnu.so")

    def test_contourpy_aarch64_elf(self):
        # Exercises pip.parse + pip.whl_mods with a PyPI meson-python C++ sdist.
        self._assert_aarch64_so("_contourpy.cpython-*-aarch64-linux-gnu.so")

    def test_tabulate_aarch64_present(self):
        root = _find_runfiles_root()
        matches = list(root.rglob("tabulate/__init__.py"))
        self.assertTrue(
            matches,
            f"Expected tabulate/__init__.py in cross-compiled outputs under {root}",
        )


if __name__ == "__main__":
    unittest.main()
