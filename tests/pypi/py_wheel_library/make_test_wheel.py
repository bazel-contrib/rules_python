"""Generate a synthetic wheel for testing py_wheel_library, py_wheel_headers, and py_wheel_transform."""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path


def _write_entry(zf: zipfile.ZipFile, name: str, content: str) -> None:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.external_attr = 0o644 << 16
    zf.writestr(info, content.encode("utf-8"))


def main() -> None:
    out_whl = Path(sys.argv[1])
    with zipfile.ZipFile(out_whl, "w") as zf:
        _write_entry(
            zf,
            "demo_pkg-1.2.3.dist-info/METADATA",
            "Metadata-Version: 2.1\nName: demo-pkg\nVersion: 1.2.3\n",
        )
        _write_entry(
            zf,
            "demo_pkg-1.2.3.dist-info/WHEEL",
            "Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
        )
        _write_entry(
            zf,
            "demo_pkg-1.2.3.dist-info/RECORD",
            "bad_top_mod.py,sha256=old,10\ndemo_pkg/__init__.py,sha256=old,10\ndemo_pkg/lib/libdemo.so,sha256=old,10\n",
        )
        _write_entry(
            zf,
            "bad_top_mod.py",
            "print 'py2 syntax'\n",
        )
        _write_entry(
            zf,
            "demo_pkg/__init__.py",
            'VALUE = "original"\nTRANSFORMED = False\n',
        )
        _write_entry(
            zf,
            "demo_pkg/include/demo_header.h",
            "#ifndef DEMO_HEADER_H\n#define DEMO_HEADER_H\n#define DEMO_MAGIC_NUMBER 42\n#endif\n",
        )
        _write_entry(
            zf,
            "demo_pkg/lib/libdemo.so",
            "fake_shared_library_bytes",
        )


if __name__ == "__main__":
    main()
