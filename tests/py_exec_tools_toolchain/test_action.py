import encodings
import json
import os
import sys
import sysconfig
from pathlib import Path

# Verify that sys.executable points to a path in runfiles.
executable = Path(sys.executable)
is_in_runfiles = ".runfiles" in executable.parts or ".runfiles" in sys.executable

if not is_in_runfiles:
    sys.exit(f"Expected sys.executable to be in runfiles, got: {sys.executable}")

if not executable.is_file():
    sys.exit(f"Expected sys.executable to be an existing file, got: {sys.executable}")

# Verify that stdlib modules came from a runfiles location.
stdlib_modules = [encodings, json, os, sysconfig]
for mod in stdlib_modules:
    mod_file = getattr(mod, "__file__", None)
    if not mod_file:
        sys.exit(f"Expected {mod.__name__} to have __file__")
    if ".runfiles" not in mod_file:
        sys.exit(f"Expected {mod.__name__} to be in runfiles, got: {mod_file}")
    if not Path(mod_file).exists():
        sys.exit(f"Expected {mod.__name__} file to exist, got: {mod_file}")

stdlib_is_in_runfiles = {
    mod.__name__: (
        getattr(mod, "__file__", None) is not None
        and ".runfiles" in getattr(mod, "__file__", "")
        and Path(getattr(mod, "__file__", "")).exists()
    )
    for mod in stdlib_modules
}

stdlib_dir = sysconfig.get_path("stdlib")
if not stdlib_dir or ".runfiles" not in stdlib_dir:
    sys.exit(f"Expected stdlib directory to be in runfiles, got: {stdlib_dir}")
if not Path(stdlib_dir).is_dir():
    sys.exit(f"Expected stdlib directory to exist on disk, got: {stdlib_dir}")

data = {
    "has_encodings": bool(encodings),
    "status": "ok",
    "stdlib_is_in_runfiles": stdlib_is_in_runfiles,
    "sys_executable_is_in_runfiles": is_in_runfiles,
}
Path(sys.argv[1]).write_bytes(
    (json.dumps(data, indent=2, sort_keys=True) + "\n").encode("utf-8"),
)
