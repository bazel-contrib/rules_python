import fnmatch
import os
import pathlib
import struct
import unittest
import zipfile

ELF_MAGIC = b"\x7fELF"
ELFCLASS64 = 2
ELFDATA2LSB = 1
EM_AARCH64 = 183


def _find_runfiles_root() -> pathlib.Path:
    runfiles_dir = os.environ.get("TEST_SRCDIR") or os.environ.get("RUNFILES_DIR")
    if not runfiles_dir:
        raise AssertionError("Neither TEST_SRCDIR nor RUNFILES_DIR is set")
    return pathlib.Path(runfiles_dir)


def _check_elf_header(header: bytes, label: str) -> None:
    magic = header[0:4]
    ei_class = header[4]
    ei_data = header[5]
    (e_machine,) = struct.unpack("<H", header[18:20])
    if magic != ELF_MAGIC:
        raise AssertionError(f"{label} is not an ELF binary")
    if ei_class != ELFCLASS64:
        raise AssertionError(f"{label} is not 64-bit ELF")
    if ei_data != ELFDATA2LSB:
        raise AssertionError(f"{label} is not little-endian ELF")
    if e_machine != EM_AARCH64:
        raise AssertionError(
            f"{label} has e_machine={e_machine}, expected EM_AARCH64 ({EM_AARCH64})"
        )


class CrossCompileTest(unittest.TestCase):
    def _assert_wheel_contains_aarch64_so(self, wheel_name: str, so_glob: str) -> None:
        root = _find_runfiles_root()
        matches = list(root.rglob(wheel_name))
        self.assertTrue(matches, f"Expected wheel {wheel_name!r} under {root}")
        with zipfile.ZipFile(matches[0]) as zf:
            so_entries = [n for n in zf.namelist() if fnmatch.fnmatch(n, so_glob)]
            self.assertTrue(
                so_entries,
                f"Expected entry matching {so_glob!r} in {matches[0]}, got {zf.namelist()}",
            )
            header = zf.read(so_entries[0])[:20]
            _check_elf_header(header, f"{matches[0]}:{so_entries[0]}")

    def test_tiny_setuptools_aarch64_elf(self):
        self._assert_wheel_contains_aarch64_so(
            "tiny_setuptools.sdist_build.whl",
            "tiny_setuptools/_tiny_st.cpython-*-aarch64-linux-gnu.so",
        )

    def test_tiny_meson_c_aarch64_elf(self):
        self._assert_wheel_contains_aarch64_so(
            "tiny_meson.sdist_build.whl",
            "tiny_meson/_tiny_c.cpython-*-aarch64-linux-gnu.so",
        )

    def test_tiny_meson_cpp_aarch64_elf(self):
        self._assert_wheel_contains_aarch64_so(
            "tiny_meson.sdist_build.whl",
            "tiny_meson/_tiny_cpp.cpython-*-aarch64-linux-gnu.so",
        )


if __name__ == "__main__":
    unittest.main()
