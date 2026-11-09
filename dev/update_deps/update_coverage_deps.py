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

"""A small script to update bazel files within the repo.

We are not running this with 'bazel run' to keep the dependencies minimal
"""

# NOTE @aignas 2023-01-09: We should only depend on core Python 3 packages.
import argparse
import json
import os
import textwrap
from dataclasses import dataclass
from typing import Any
from urllib import request

from dev.update_deps.args import path_from_runfiles
from dev.update_deps.update_file import update_file


@dataclass
class Whl:
    url: str
    sha256: str
    marker: str

    def __repr__(self):
        return "\n".join(
            [
                "struct(",
                f'    url = "{self.url}",',
                f'    hash = "sha256:{self.sha256}",',
                f"    marker = {json.dumps(self.marker)},",
                "),",
            ]
        )


@dataclass
class Whls:
    whls: list[Whl]

    def __repr__(self):
        inner = textwrap.indent(
            "\n".join([repr(w) for w in self.whls]),
            prefix="    ",
        )
        return "[\n{}\n]".format(inner)


def _whl(url: str, digests: dict[str, str], marker: str, **kwargs: Any) -> Whl:
    return Whl(
        url=url,
        sha256=digests["sha256"],
        marker=marker,
    )


@dataclass
class VersionSpec:
    """A package version and the PEP 508 marker for when to use it."""

    version: str
    marker: str


def _parse_version_spec(value: str) -> VersionSpec:
    version, _, marker = value.partition(";")
    version = version.strip()
    if not version:
        raise argparse.ArgumentTypeError(
            f"Expected '<version>[; <marker>]', got '{value}'"
        )
    return VersionSpec(version=version, marker=marker.strip())


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument(
        "--name",
        default="coverage",
        type=str,
        help="The name of the package",
    )
    parser.add_argument(
        "versions",
        nargs="+",
        type=_parse_version_spec,
        help=(
            "The versions of the package to download, each optionally with a "
            "PEP 508 environment marker for when the version should be used, "
            "e.g. \"7.10.7; python_full_version < '3.15'\". The markers should not "
            "overlap."
        ),
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


def _get_urls(name: str, version: str) -> list[dict[str, Any]]:
    api_url = f"https://pypi.org/pypi/{name}/{version}/json"
    req = request.Request(api_url)
    with request.urlopen(req) as response:
        data = json.loads(response.read().decode("utf-8"))
    return data["urls"]


def main():
    args = _parse_args()

    whls = []
    for spec in args.versions:
        for u in _get_urls(args.name, spec.version):
            if u["yanked"]:
                continue

            if not u["filename"].endswith(".whl"):
                continue

            whls.append(_whl(marker=spec.marker, **u))

    whls.sort(key=lambda x: x.url.rpartition("/")[2])

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
