"""Exercise failure and cancellation before the helper's readiness message."""

import os
import time
from pathlib import Path

if root := os.environ.get("CLEANUP_HELPER_STARTUP_PROBE"):
    parent = os.getppid()
    os.setsid()
    Path(root, "helper_starting").write_text(str(os.getpid()))
    while os.getppid() == parent:
        time.sleep(0.01)
    Path(root, "helper_finished").touch()

raise SystemExit(23)
