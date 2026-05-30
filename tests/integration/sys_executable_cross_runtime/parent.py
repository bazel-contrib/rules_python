import os
import subprocess
import sys

from python.runfiles import Runfiles


def main() -> int:
    assert len(sys.argv) == 2
    mode = sys.argv[1]
    runfiles = Runfiles.Create()
    child = runfiles.Rlocation("_main/child")
    assert child is not None

    # Reproduce the broken contract: the parent exports its own runtime import
    # paths, then starts the child launcher with sys.executable. The child
    # launcher re-execs into its own interpreter, but the inherited PYTHONPATH
    # still points at the parent's stdlib and site-packages.
    os.environ["PYTHONPATH"] = os.pathsep.join(sys.path)

    if mode == "sys_executable":
        argv = [sys.executable, child]
    elif mode == "direct":
        argv = [child]
    else:
        raise RuntimeError(f"unknown launch mode: {mode}")

    proc = subprocess.run(
        argv,
        check=False,
    )
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
