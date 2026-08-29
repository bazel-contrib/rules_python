"""Rewrites a console_script wrapper's shebang into a batch/shell-Python polyglot."""

import os
import sys


def main(argv):
    in_path, out_path, target_os = argv[1:4]

    with open(in_path, "rb") as in_file:
        first_line = in_file.readline()
        rest = in_file.read()

    with open(out_path, "wb") as out_file:
        if target_os == "windows":
            python_exe = b"pythonw.exe" if first_line.startswith(b"#!pythonw") else b"python.exe"
            # A Batch-Python polyglot. Batch executes the first line and exits,
            # while Python (via -x) ignores the first line and executes the rest.
            out_file.write(
                b'@setlocal enabledelayedexpansion & "%~dp0' + python_exe +
                b'" -x "%~f0" %* & exit /b !ERRORLEVEL!\r\n',
            )
        else:
            out_file.write(b"#!/bin/sh\n")
            # A Shell-Python polyglot. The shell executes the triple-quoted 'exec'
            # command, re-running the script with python3 from the scripts directory.
            # Python ignores the triple-quoted string and continues.
            out_file.write(b"'''exec' \"$(dirname \"$0\")/python3\" \"$0\" \"$@\"\n' '''\n")

        out_file.write(rest)

    mode = os.stat(out_path).st_mode
    os.chmod(out_path, mode | 0o111)


if __name__ == "__main__":
    main(sys.argv)
