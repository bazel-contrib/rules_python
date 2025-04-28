"""Simulates the REPL that Python spawns when invoking the binary with no arguments.

The code module is responsible for the default shell.

The import and `ocde.interact()` call here his is equivalent to doing:

    $ python3 -m code
    Python 3.11.2 (main, Mar 13 2023, 12:18:29) [GCC 12.2.0] on linux
    Type "help", "copyright", "credits" or "license" for more information.
    (InteractiveConsole)
    >>>

The logic for PYTHONSTARTUP is handled in python/private/repl_template.py.
"""

import code

code.interact()
