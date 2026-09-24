"""User startup hook, also used to pause before stage two starts."""

import os
import signal
import time
from pathlib import Path


def user_interrupt(_signum, _frame):
    raise SystemExit(19)


signal.signal(signal.SIGINT, user_interrupt)
if directory := os.environ.get("CLEANUP_STARTUP_PROBE"):
    root = Path(directory)
    (root / "starting").touch()
    while not (root / "continue").exists():
        time.sleep(0.01)
