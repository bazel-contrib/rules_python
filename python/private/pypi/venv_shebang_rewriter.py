"""Rewrites a console_script wrapper's shebang into a batch/shell-Python polyglot.

Usage:
    venv_shebang_rewriter.py <in_path> <out_path> <target_os>

Input file format:
    A wheel `.data/scripts/*` script whose first line starts with `#!python`
    (or `#!pythonw`).
"""

from __future__ import annotations

import os
import sys
from collections.abc import Sequence


def rewrite_shebang_bytes(content: bytes, target_os: str) -> bytes:
    """Replace the leading `#!python` shebang line with a portable polyglot header."""
    nl = content.find(b"\n")
    if nl == -1:
        first_line = content
        rest = b""
    else:
        first_line = content[: nl + 1]
        rest = content[nl + 1 :]

    if target_os == "windows":
        python_exe = (
            b"pythonw.exe" if first_line.startswith(b"#!pythonw") else b"python.exe"
        )
        # A Batch-Python polyglot. Batch executes the first line and exits,
        # while Python (via -x) ignores the first line and executes the rest.
        header = (
            b'@setlocal enabledelayedexpansion & "%~dp0'
            + python_exe
            + b'" -x "%~f0" %* & exit /b !ERRORLEVEL!\r\n'
        )
    else:
        # A Shell-Python polyglot. The shell executes the triple-quoted 'exec'
        # command, re-running the script with python3 from the scripts directory.
        # Python ignores the triple-quoted string and continues.
        header = (
            b"#!/bin/sh\n'''exec' \"$(dirname \"$0\")/python3\" \"$0\" \"$@\"\n' '''\n"
        )
    return header + rest


def main(argv: Sequence[str] | None = None) -> None:
    args = sys.argv[1:] if argv is None else argv
    in_path, out_path, target_os = args[:3]

    with open(in_path, "rb") as in_file:
        content = in_file.read()

    with open(out_path, "wb") as out_file:
        out_file.write(rewrite_shebang_bytes(content, target_os))

    mode = os.stat(out_path).st_mode
    os.chmod(out_path, mode | 0o111)


if __name__ == "__main__":
    main()
