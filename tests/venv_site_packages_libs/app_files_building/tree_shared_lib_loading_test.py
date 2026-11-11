"""Runtime test loading C extensions and shared libraries from a tree-backed venv."""

from __future__ import annotations

import ctypes
import importlib
import importlib.util
import os
import sys
import unittest
from pathlib import Path

# Platform-conditional binary header parsers (pyelftools on Linux, macholib on macOS).
if os.name == "posix" and sys.platform != "darwin":
    from elftools.elf.elffile import ELFFile  # pyrefly: ignore[missing-import]
else:
    ELFFile = None

if sys.platform == "darwin":
    from macholib import mach_o  # pyrefly: ignore[missing-import]
    from macholib.MachO import MachO  # pyrefly: ignore[missing-import]
else:
    mach_o = None
    MachO = None

_ELF_MAGIC = b"\x7fELF"
_MACHO_MAGICS = (
    b"\xce\xfa\xed\xfe",  # 32-bit big-endian
    b"\xcf\xfa\xed\xfe",  # 64-bit big-endian
    b"\xfe\xed\xfa\xce",  # 32-bit little-endian
    b"\xfe\xed\xfa\xcf",  # 64-bit little-endian
)


class TreeSharedLibLoadingTest(unittest.TestCase):
    def setUp(self) -> None:
        super().setUp()
        if sys.prefix == sys.base_prefix:
            raise AssertionError("Not running under a venv")
        self.venv = Path(sys.prefix)

    def test_tree_backed_shared_library_linking(self) -> None:
        try:
            adder = importlib.import_module("tree_ext_with_libs.adder")
        except ImportError as err:
            spec = importlib.util.find_spec("tree_ext_with_libs.adder")
            if not spec or not spec.origin:
                self.fail(f"Import failed and could not find module spec: {err}")

            info = self._get_linking_info(spec.origin)
            self.fail(
                f"Failed to import tree_ext_with_libs.adder.\n"
                f"Original error: {err}\n"
                f"Linking info for {spec.origin}:\n"
                f"  RPATHs: {info.get('rpaths', 'N/A')}\n"
                f"  Needed libs: {info.get('needed', 'N/A')}"
            )

        self.assertIsNotNone(adder.__file__)
        assert adder.__file__ is not None  # type assert
        self.assertIn(".venv/", adder.__file__)

        adder_venv_path = Path(adder.__file__)
        self.assertTrue(
            str(adder_venv_path).startswith(str(self.venv)),
            f"Extension {adder_venv_path} was not loaded from venv {self.venv}",
        )

        # Shared libraries must be linked directly as file symlinks rather than
        # via a directory symlink on the enclosing package or `libs/` directory.
        pkg_dir = adder_venv_path.parent
        libs_dir = pkg_dir / "libs"
        libincrement_name = (
            "libincrement.dylib" if sys.platform == "darwin" else "libincrement.so"
        )
        increment_venv_path = libs_dir / libincrement_name

        self.assertTrue(pkg_dir.is_dir())
        self.assertFalse(
            pkg_dir.is_symlink(),
            f"Expected {pkg_dir} to be a real directory, not a symlink",
        )
        self.assertTrue(libs_dir.is_dir())
        self.assertFalse(
            libs_dir.is_symlink(),
            f"Expected {libs_dir} to be a real directory, not a symlink",
        )
        self.assertTrue(
            adder_venv_path.is_symlink(),
            f"Expected {adder_venv_path} to be a direct file symlink",
        )
        self.assertTrue(
            increment_venv_path.is_symlink(),
            f"Expected {increment_venv_path} to be a direct file symlink",
        )

        adder_real = adder_venv_path.resolve()
        increment_real = increment_venv_path.resolve()
        self.assertEqual(adder_real.parent / "libs" / libincrement_name, increment_real)
        self.assertIn("tree_ext_with_libs_srcs/", adder_real.as_posix())
        self.assertIn("tree_ext_with_libs_srcs/", increment_real.as_posix())

        with open(adder_real, "rb") as f:
            magic_bytes = f.read(4)

        if magic_bytes == _ELF_MAGIC:
            self._assert_elf_linking(str(adder_real))
        elif magic_bytes in _MACHO_MAGICS:
            self._assert_macho_linking(str(adder_real))
        else:
            self.fail(f"Unsupported file format for adder: magic bytes {magic_bytes!r}")

        self.assertEqual(adder.do_add(), 2)

        loaded_libs = self._get_loaded_shared_libs()
        self.assertIn(adder_real, loaded_libs)
        self.assertIn(increment_real, loaded_libs)

    def _get_loaded_shared_libs(self) -> set[Path]:
        if sys.platform == "darwin":
            libsystem = ctypes.CDLL(None)
            dyld_image_count = libsystem._dyld_image_count
            dyld_image_count.argtypes = []
            dyld_image_count.restype = ctypes.c_uint32
            dyld_get_image_name = libsystem._dyld_get_image_name
            dyld_get_image_name.argtypes = [ctypes.c_uint32]
            dyld_get_image_name.restype = ctypes.c_char_p
            loaded: set[Path] = set()
            for idx in range(dyld_image_count()):
                raw_name = dyld_get_image_name(idx)
                if raw_name is not None:
                    loaded.add(Path(os.fsdecode(raw_name)).resolve())
            return loaded

        loaded = set()
        with open("/proc/self/maps", encoding="utf-8") as maps_file:
            for line in maps_file:
                parts = line.split(maxsplit=5)
                if len(parts) == 6 and parts[5].startswith("/"):
                    mapped = parts[5].strip()
                    if not mapped.endswith(" (deleted)"):
                        loaded.add(Path(mapped).resolve())
        return loaded

    def _get_linking_info(self, path: str) -> dict[str, list[str]]:
        real_path = os.path.realpath(path)
        with open(real_path, "rb") as f:
            magic_bytes = f.read(4)

        if magic_bytes == _ELF_MAGIC:
            return self._get_elf_info(real_path)
        if magic_bytes in _MACHO_MAGICS:
            return self._get_macho_info(real_path)
        return {}

    def _get_elf_info(self, path: str) -> dict[str, list[str]]:
        assert ELFFile is not None  # type assert
        info: dict[str, list[str]] = {
            "rpaths": [],
            "needed": [],
            "undefined_symbols": [],
        }
        with open(path, "rb") as f:
            elf = ELFFile(f)
            dynamic = elf.get_section_by_name(".dynamic")
            if dynamic:
                for tag in dynamic.iter_tags():
                    # pyelftools generates tag attributes dynamically by d_tag kind.
                    if tag.entry.d_tag == "DT_NEEDED":  # pyrefly: ignore[missing-attribute]
                        info["needed"].append(tag.needed)  # pyrefly: ignore[missing-attribute]
                    elif tag.entry.d_tag == "DT_RPATH":  # pyrefly: ignore[missing-attribute]
                        info["rpaths"].append(tag.rpath)  # pyrefly: ignore[missing-attribute]
                    elif tag.entry.d_tag == "DT_RUNPATH":  # pyrefly: ignore[missing-attribute]
                        info["rpaths"].append(tag.runpath)  # pyrefly: ignore[missing-attribute]

            dynsym = elf.get_section_by_name(".dynsym")
            if dynsym:
                info["undefined_symbols"] = [
                    s.name
                    for s in dynsym.iter_symbols()
                    if s.entry["st_shndx"] == "SHN_UNDEF"  # pyrefly: ignore[missing-attribute]
                ]
        return info

    def _get_macho_info(self, path: str) -> dict[str, list[str]]:
        assert MachO is not None and mach_o is not None  # type assert
        info: dict[str, list[str]] = {"rpaths": [], "needed": []}
        macho = MachO(path)
        for header in macho.headers:
            for cmd_load, _, data in header.commands:
                if cmd_load.cmd == mach_o.LC_LOAD_DYLIB:
                    info["needed"].append(data.decode().strip("\x00"))
                elif cmd_load.cmd == mach_o.LC_RPATH:
                    info["rpaths"].append(data.decode().strip("\x00"))
        return info

    def _assert_elf_linking(self, path: str) -> None:
        info = self._get_elf_info(path)
        self.assertIn("libincrement.so", info["needed"])
        self.assertIn("increment", info["undefined_symbols"])
        self.assertTrue(
            any("$ORIGIN/libs" in rpath for rpath in info["rpaths"]),
            f"Expected $ORIGIN/libs in ELF rpaths, got {info['rpaths']}",
        )

    def _assert_macho_linking(self, path: str) -> None:
        info = self._get_macho_info(path)
        self.assertIn("@rpath/libincrement.dylib", info["needed"])
        self.assertTrue(
            any("@loader_path/libs" in rpath for rpath in info["rpaths"]),
            f"Expected @loader_path/libs in Mach-O rpaths, got {info['rpaths']}",
        )


if __name__ == "__main__":
    unittest.main()
