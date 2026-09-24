"""A pipeline peer that needs its original foreground terminal group."""

import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
with open("/dev/tty") as terminal:
    (root / "peer_ready").write_text(str(os.getpid()))
    assert terminal.readline().strip() == "finish"
(root / "peer_done").touch()
