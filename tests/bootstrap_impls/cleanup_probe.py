"""Application used to observe temporary-runtime launchers from the outside."""

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def main():
    mode = sys.argv[1]
    if mode == "nested":
        child = subprocess.run(
            sys.argv[2:],
            input=sys.stdin.read(),
            text=True,
            capture_output=True,
            check=False,
        )
        print(child.stdout, end="")
        print(child.stderr, end="", file=sys.stderr)
        return child.returncode
    if mode == "wait_children":
        # A cleanup watcher left as our child would make this block forever.
        try:
            while True:
                os.waitpid(-1, 0)
        except ChildProcessError:
            return 0
    if mode == "echo":
        print(
            json.dumps(
                {
                    "argv": sys.argv[3:],
                    "stdin": sys.stdin.read(),
                    "executable": sys.executable,
                    "pid": os.getpid(),
                    "pgid": os.getpgrp(),
                    "ignored": [
                        signal.getsignal(value) == signal.SIG_IGN
                        for value in (signal.SIGINT, signal.SIGQUIT)
                    ],
                    "handler": getattr(signal.getsignal(signal.SIGINT), "__name__", ""),
                    "xoptions": sys._xoptions,
                    "cwd": os.getcwd(),
                    "runfiles": os.environ.get("RUNFILES_DIR"),
                    "additional_args": os.environ.get(
                        "RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS"
                    ),
                    "safe_path": os.environ.get("PYTHONSAFEPATH"),
                }
            )
        )
        return int(sys.argv[2])

    root = Path(sys.argv[2])
    if mode == "close_fds":
        for fd in (0, 1, 2, int(sys.argv[3])):
            os.close(fd)
        (root / "ready").touch()
        while not (root / "finish").exists():
            time.sleep(0.01)
        return 0

    if mode == "handled":

        def stop(signum, _frame):
            for value in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT):
                signal.signal(value, signal.SIG_IGN)
            raise SystemExit(128 + signum)

        for value in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT):
            signal.signal(value, stop)

    try:
        # Announce readiness only once the cleanup handler is active and the
        # complete PID can be read. Signals may arrive immediately afterward.
        (root / "ready.tmp").write_text(str(os.getpid()))
        (root / "ready.tmp").replace(root / "ready")
        if mode == "pipeline":
            while not (root / "peer_done").exists():
                time.sleep(0.01)
            return 0
        if sys.stdin.readline().strip() == "finish":
            return 0
        raise AssertionError("expected cancellation or foreground input")
    finally:
        (root / "stopping").touch()
        if mode in ("handled", "interrupt"):
            assert sys.stdin.readline().strip() == "cleanup"
        assert Path(sys.executable).is_file(), (
            "runtime removed before application cleanup"
        )
        (root / "cleaned").touch()


if __name__ == "__main__":
    sys.exit(main())
