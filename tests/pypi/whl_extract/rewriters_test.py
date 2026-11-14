"""Unit tests for venv_shebang_rewriter and wheel_record_rewriter helpers."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from python.private.pypi import venv_shebang_rewriter, wheel_record_rewriter


class RewritersTest(unittest.TestCase):
    def test_rewrite_shebang_posix_and_windows(self) -> None:
        src = b"#!python\nimport sys\nprint(sys.executable)\n"
        posix_out = venv_shebang_rewriter.rewrite_shebang_bytes(src, "linux")
        self.assertTrue(posix_out.startswith(b"#!/bin/sh\n'''exec' "))
        self.assertTrue(posix_out.endswith(b"import sys\nprint(sys.executable)\n"))

        win_out = venv_shebang_rewriter.rewrite_shebang_bytes(src, "windows")
        self.assertIn(b"python.exe", win_out)
        self.assertTrue(win_out.endswith(b"import sys\nprint(sys.executable)\n"))

        gui_out = venv_shebang_rewriter.rewrite_shebang_bytes(
            b"#!pythonw\nprint(1)\n", "windows"
        )
        self.assertIn(b"pythonw.exe", gui_out)

    def test_shebang_main_writes_executable_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            in_file = Path(tmp) / "in_script"
            out_file = Path(tmp) / "out_script"
            in_file.write_bytes(b"#!python\nprint('hi')\n")
            venv_shebang_rewriter.main([str(in_file), str(out_file), "linux"])
            self.assertIn(b"#!/bin/sh\n", out_file.read_bytes())

    def test_rewrite_record_lines_posix_and_windows(self) -> None:
        lines = [
            "pkg/__init__.py,sha256=abc,10\r\n",
            "pkg-1.0.data/purelib/pure.py,sha256=def,20\n",
            "pkg-1.0.data/scripts/mytool,sha256=ghi,30\n",
            "pkg-1.0.data/scripts/native_bin,sha256=jkl,40\n",
            '"pkg-1.0.data/scripts/quoted,tool",sha256=mno,50\n',
            "pkg-1.0.data/headers/hdr.h,sha256=pqr,60\n",
            "pkg-1.0.data/data/share/doc.txt,sha256=stu,70\n",
        ]
        posix = wheel_record_rewriter.rewrite_record_lines(
            lines, "linux", "pkg-1.0.data", {"mytool", "quoted,tool"}
        )
        self.assertEqual(
            posix,
            [
                "pkg/__init__.py,sha256=abc,10\n",
                "pure.py,sha256=def,20\n",
                "../../../bin/mytool,sha256=ghi,30\n",
                "../../../bin/native_bin,sha256=jkl,40\n",
                '"../../../bin/quoted,tool",sha256=mno,50\n',
                "../../../include/hdr.h,sha256=pqr,60\n",
                "../../../share/doc.txt,sha256=stu,70\n",
            ],
        )

        windows = wheel_record_rewriter.rewrite_record_lines(
            lines, "windows", "pkg-1.0.data", {"mytool", "quoted,tool"}
        )
        self.assertEqual(
            windows,
            [
                "pkg/__init__.py,sha256=abc,10\n",
                "pure.py,sha256=def,20\n",
                "../../Scripts/mytool.bat,sha256=ghi,30\n",
                "../../Scripts/native_bin,sha256=jkl,40\n",
                '"../../Scripts/quoted,tool.bat",sha256=mno,50\n',
                "../../Include/hdr.h,sha256=pqr,60\n",
                "../../share/doc.txt,sha256=stu,70\n",
            ],
        )

    def test_record_main_writes_lf_newlines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            in_file = Path(tmp) / "RECORD.in"
            out_file = Path(tmp) / "RECORD"
            in_file.write_bytes(b"pkg-1.0.data/scripts/tool,sha256=a,1\r\n")
            wheel_record_rewriter.main(
                [str(in_file), str(out_file), "windows", "pkg-1.0.data", "tool"]
            )
            self.assertEqual(
                out_file.read_bytes(),
                b"../../Scripts/tool.bat,sha256=a,1\n",
            )

    def test_malformed_quoted_scripts_entry_raises(self) -> None:
        with self.assertRaises(ValueError):
            wheel_record_rewriter.rewrite_record_lines(
                ['"pkg-1.0.data/scripts/broken,sha256=x,1\n'],
                "windows",
                "pkg-1.0.data",
                set(),
            )


if __name__ == "__main__":
    unittest.main()
