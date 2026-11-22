"""Runtime test loading C extensions and shared libraries from a tree-backed venv."""

from __future__ import annotations

import ctypes
import importlib
import importlib.util
import os
import sys
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


def _get_loaded_shared_libs() -> set[Path]:
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


def _get_elf_info(path: str) -> dict[str, list[str]]:
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


def _get_macho_info(path: str) -> dict[str, list[str]]:
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


def _get_linking_info(path: str) -> dict[str, list[str]]:
    real_path = os.path.realpath(path)
    with open(real_path, "rb") as f:
        magic_bytes = f.read(4)

    if magic_bytes == _ELF_MAGIC:
        return _get_elf_info(real_path)
    if magic_bytes in _MACHO_MAGICS:
        return _get_macho_info(real_path)
    return {}


def _assert_elf_linking(path: str) -> None:
    info = _get_elf_info(path)
    assert "libincrement.so" in info["needed"]
    assert "increment" in info["undefined_symbols"]
    assert any("$ORIGIN/libs" in rpath for rpath in info["rpaths"]), (
        f"Expected $ORIGIN/libs in ELF rpaths, got {info['rpaths']}"
    )


def _assert_macho_linking(path: str) -> None:
    info = _get_macho_info(path)
    assert "@rpath/libincrement.dylib" in info["needed"]
    assert any("@loader_path/libs" in rpath for rpath in info["rpaths"]), (
        f"Expected @loader_path/libs in Mach-O rpaths, got {info['rpaths']}"
    )


def test_tree_backed_shared_library_linking() -> None:
    assert sys.prefix != sys.base_prefix, "Not running under a venv"
    venv = Path(sys.prefix)

    try:
        adder = importlib.import_module("tree_ext_with_libs.adder")
    except ImportError as err:
        spec = importlib.util.find_spec("tree_ext_with_libs.adder")
        if not spec or not spec.origin:
            raise AssertionError(
                f"Import failed and could not find module spec: {err}"
            ) from err

        info = _get_linking_info(spec.origin)
        raise AssertionError(
            f"Failed to import tree_ext_with_libs.adder.\n"
            f"Original error: {err}\n"
            f"Linking info for {spec.origin}:\n"
            f"  RPATHs: {info.get('rpaths', 'N/A')}\n"
            f"  Needed libs: {info.get('needed', 'N/A')}"
        ) from err

    assert adder.__file__ is not None
    assert ".venv/" in adder.__file__

    adder_venv_path = Path(adder.__file__)
    assert str(adder_venv_path).startswith(str(venv)), (
        f"Extension {adder_venv_path} was not loaded from venv {venv}"
    )

    # Shared libraries must be linked directly as file symlinks rather than
    # via a directory symlink on the enclosing package or `libs/` directory.
    pkg_dir = adder_venv_path.parent
    libs_dir = pkg_dir / "libs"
    libincrement_name = (
        "libincrement.dylib" if sys.platform == "darwin" else "libincrement.so"
    )
    increment_venv_path = libs_dir / libincrement_name

    assert pkg_dir.is_dir()
    assert not pkg_dir.is_symlink(), (
        f"Expected {pkg_dir} to be a real directory, not a symlink"
    )
    assert libs_dir.is_dir()
    assert not libs_dir.is_symlink(), (
        f"Expected {libs_dir} to be a real directory, not a symlink"
    )
    assert adder_venv_path.is_symlink(), (
        f"Expected {adder_venv_path} to be a direct file symlink"
    )
    assert increment_venv_path.is_symlink(), (
        f"Expected {increment_venv_path} to be a direct file symlink"
    )

    adder_real = adder_venv_path.resolve()
    increment_real = increment_venv_path.resolve()
    assert adder_real.parent / "libs" / libincrement_name == increment_real
    assert "tree_ext_with_libs_srcs/" in adder_real.as_posix()
    assert "tree_ext_with_libs_srcs/" in increment_real.as_posix()

    with open(adder_real, "rb") as f:
        magic_bytes = f.read(4)

    if magic_bytes == _ELF_MAGIC:
        _assert_elf_linking(str(adder_real))
    elif magic_bytes in _MACHO_MAGICS:
        _assert_macho_linking(str(adder_real))
    else:
        raise AssertionError(
            f"Unsupported file format for adder: magic bytes {magic_bytes!r}"
        )

    assert adder.do_add() == 2

    loaded_libs = _get_loaded_shared_libs()
    assert adder_real in loaded_libs
    assert increment_real in loaded_libs
