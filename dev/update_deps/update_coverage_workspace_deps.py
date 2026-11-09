"""Update the generated `workspace_deps.bzl` file for the coverage tool.

Usage:
    bazel run //dev/update_deps:update_coverage_workspace_deps
"""

import os
import pathlib
import shutil

from python.runfiles import runfiles


def main() -> None:
    r = runfiles.CreateOrRaise()
    generated = r.Rlocation(os.environ["GENERATED"])
    if not generated:
        raise FileNotFoundError(os.environ["GENERATED"])
    src = pathlib.Path(generated)
    dst = (
        pathlib.Path(os.environ["BUILD_WORKSPACE_DIRECTORY"])
        / "python/private/coverage/workspace_deps.bzl"
    )
    shutil.copyfile(src, dst)
    print(f"Updated {dst}")


if __name__ == "__main__":
    main()
