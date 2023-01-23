# std_modules.py is a long-living program that communicates over STDIN and
# STDOUT. STDIN receives module names, one per line. For each module statement
# it evaluates, it outputs true/false for whether the module is part of the
# standard library or not.

import os
import sys
from contextlib import redirect_stdout


def is_std_modules(module):
    # If for some reason a module (such as pygame, see https://github.com/pygame/pygame/issues/542)
    # prints to stdout upon import,
    # the output of this script should still be parseable by golang.
    # Therefore, redirect stdout while running the import.
    with redirect_stdout(os.devnull):
        try:
            __import__(module, globals(), locals(), [], 0)
            return True
        except Exception:
            return False


def main(stdin, stdout):
    for module in stdin:
        module = module.strip()
        # Don't print the boolean directly as it is capitalized in Python.
        print(
            "true" if is_std_modules(module) else "false",
            end="\n",
            file=stdout,
        )
        stdout.flush()


if __name__ == "__main__":
    exit(main(sys.stdin, sys.stdout))
