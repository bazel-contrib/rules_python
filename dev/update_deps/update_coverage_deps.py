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
    filename: str
    url: str
    sha256: str

    def __repr__(self):
        return "\n".join(
            [
                "struct(",
                f'    url = "{self.url}",',
                f'    hash = "sha256:{self.sha256}",',
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


def _whl(filename: str, url: str, digests: dict[str, str], **kwargs: Any) -> Whl:
    return Whl(
        filename=filename,
        url=url,
        sha256=digests["sha256"],
    )


@dataclass
class VersionSpec:
    """A package version and the CPython minor versions to take wheels for."""

    version: str
    min_minor: int
    max_minor: int

    def matches(self, python_tag: str) -> bool:
        if not python_tag.startswith("cp3"):
            return False

        minor = python_tag[len("cp3") :]
        return minor.isdigit() and self.min_minor <= int(minor) <= self.max_minor


def _parse_py_tag(tag: str) -> int:
    if not tag.startswith("cp3") or not tag[len("cp3") :].isdigit():
        raise argparse.ArgumentTypeError(f"Expected a 'cp3<minor>' tag, got '{tag}'")
    return int(tag[len("cp3") :])


def _parse_version_spec(value: str) -> VersionSpec:
    version, sep, py_range = value.partition(":")
    if not sep or not version or not py_range:
        raise argparse.ArgumentTypeError(
            f"Expected '<version>:<cp3X>[-<cp3Y>]', got '{value}'"
        )

    lo, _, hi = py_range.partition("-")
    spec = VersionSpec(
        version=version,
        min_minor=_parse_py_tag(lo),
        max_minor=_parse_py_tag(hi or lo),
    )
    if spec.min_minor > spec.max_minor:
        raise argparse.ArgumentTypeError(f"Invalid python range in '{value}'")
    return spec


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
            "The versions of the package to download, each with the range of "
            "the CPython versions to take the wheels for, e.g. "
            "'7.10.7:cp39-cp314 7.17.0:cp315'. The 'py3-none-any' wheel of the "
            "first version is used as the fallback for platforms without a "
            "platform specific wheel."
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
    for i, spec in enumerate(args.versions):
        for u in _get_urls(args.name, spec.version):
            if u["yanked"]:
                continue

            if not u["filename"].endswith(".whl"):
                continue

            if u["filename"].endswith("-py3-none-any.whl"):
                # Only a single fallback wheel is needed.
                if i == 0:
                    whls.append(_whl(**u))
                continue

            if not spec.matches(u["python_version"]):
                continue

            whls.append(_whl(**u))

    whls.sort(key=lambda x: x.filename)

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
