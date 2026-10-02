"""Opt-in preparation diagnostics without application arguments or environment."""

import os
import sys


def verbose(event, *paths):
    if os.environ.get("RULES_PYTHON_BOOTSTRAP_VERBOSE"):
        print("rules_python bootstrap:", event, *paths, file=sys.stderr, flush=True)
