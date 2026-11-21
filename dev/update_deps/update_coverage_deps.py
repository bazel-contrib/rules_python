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
    min_python: tuple[int, int] | None
    max_python: tuple[int, int] | None

    def __repr__(self):
        return "\n".join(
            [
                "struct(",
                f'    url = "{self.url}",',
                f'    hash = "sha256:{self.sha256}",',
                f"    min_python = {self.min_python!r},",
                f"    max_python = {self.max_python!r},",
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


def _whl(
    url: str,
    digests: dict[str, str],
    min_python: tuple[int, int] | None,
    max_python: tuple[int, int] | None,
    **kwargs: Any,
) -> Whl:
    return Whl(
        url=url,
        sha256=digests["sha256"],
        min_python=min_python,
        max_python=max_python,
    )


@dataclass
class VersionSpec:
    """A package version and the first Python version to use it with."""

    version: str
    min_python: tuple[int, int] | None


def _parse_version_spec(value: str) -> VersionSpec:
    error = argparse.ArgumentTypeError(
        f"Expected '<version>[@<major>.<minor>]', got '{value}'"
    )
    version, at, python = value.partition("@")
    version = version.strip()
    if not version:
        raise error

    if not at:
        return VersionSpec(version=version, min_python=None)

    major, _, minor = python.strip().partition(".")
    if not major.isdigit() or not minor.isdigit():
        raise error

    return VersionSpec(version=version, min_python=(int(major), int(minor)))


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
            "The versions of the package to download, each optionally with "
            "the first Python version that it should be used with, e.g. "
            "'7.10.7 7.17.0@3.15' uses 7.17.0 with Python 3.15 and newer and "
            "7.10.7 with the older Python versions."
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

    # Each version is used until the first Python version of the next one.
    specs = sorted(args.versions, key=lambda x: x.min_python or (0, 0))
    max_pythons = [s.min_python for s in specs[1:]] + [None]

    whls = []
    for spec, max_python in zip(specs, max_pythons):
        for u in _get_urls(args.name, spec.version):
            if u["yanked"]:
                continue

            if not u["filename"].endswith(".whl"):
                continue

            whls.append(_whl(min_python=spec.min_python, max_python=max_python, **u))

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
