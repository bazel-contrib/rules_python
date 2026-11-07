#!/usr/bin/python3 -B
# Copyright 2023 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Update the bundled coverage wheels from the coverage `uv.lock` file.

The coverage versions are defined in `//dev/update_deps/coverage:pyproject.toml`
and locked with `bazel run //dev/update_deps/coverage:uv_lock.update`.
"""

# NOTE @aignas 2023-01-09: We should only depend on core Python 3 packages.
import argparse
import json
import os
import pathlib
import textwrap
from dataclasses import dataclass
from typing import Any

import tomllib

from dev.update_deps.args import path_from_runfiles
from dev.update_deps.update_file import update_file


@dataclass
class Whl:
    filename: str
    url: str
    hash: str
    marker: str

    def __repr__(self):
        lines = [
            "struct(",
            f'    url = "{self.url}",',
            f'    hash = "{self.hash}",',
        ]
        if self.marker:
            if '"' in self.marker and "'" not in self.marker:
                marker = f"'{self.marker}'"
            else:
                marker = json.dumps(self.marker)
            lines.append(f"    marker = {marker},")
        lines.append("),")
        return "\n".join(lines)


@dataclass
class Whls:
    whls: list[Whl]

    def __repr__(self):
        inner = textwrap.indent(
            "\n".join([repr(w) for w in self.whls]),
            prefix="    ",
        )
        return "[\n{}\n]".format(inner)


def _marker(markers: list[str]) -> str:
    if len(markers) == 1:
        return markers[0]

    return " or ".join(f"({m})" for m in markers)


def get_whls(uv_lock: dict[str, Any], name: str) -> list[Whl]:
    """Get all of the wheels for the given package from the parsed uv.lock."""
    whls = []
    for pkg in uv_lock.get("package", []):
        if pkg["name"] != name:
            continue

        marker = _marker(pkg.get("resolution-markers", []))
        for wheel in pkg.get("wheels", []):
            url = wheel["url"]
            whls.append(
                Whl(
                    filename=url.rpartition("/")[2],
                    url=url,
                    hash=wheel["hash"],
                    marker=marker,
                )
            )

    whls.sort(key=lambda x: x.filename)
    return whls


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument(
        "--name",
        default="coverage",
        type=str,
        help="The name of the package",
    )
    parser.add_argument(
        "--uv-lock",
        type=path_from_runfiles,
        default=os.environ.get("UV_LOCK"),
        help="The path to the uv.lock file, defaults to the value taken from UV_LOCK",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Whether to write to files",
    )
    parser.add_argument(
        "--update-file",
        type=path_from_runfiles,
        default=os.environ.get("UPDATE_FILE"),
        help="The path for the file to be updated, defaults to the value taken from UPDATE_FILE",
    )
    return parser.parse_args()


def main():
    args = _parse_args()

    uv_lock = tomllib.loads(pathlib.Path(args.uv_lock).read_text())
    whls = get_whls(uv_lock, args.name)
    if not whls:
        raise RuntimeError(f"No wheels for '{args.name}' found in {args.uv_lock}")

    # Update the coverage wheels, the compatible wheel is selected in Starlark
    update_file(
        path=args.update_file,
        snippet="_coverage_wheels = {}\n".format(repr(Whls(whls))),
        start_marker="# START: maintained by 'bazel run //dev/update_deps:update_coverage_deps <version>'",
        end_marker="# END: maintained by 'bazel run //dev/update_deps:update_coverage_deps <version>'",
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
