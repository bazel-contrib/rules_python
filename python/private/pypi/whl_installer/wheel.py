# Copyright 2023 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Utility class to inspect an extracted wheel directory"""

import email
from pathlib import Path

import installer


class DoNothingCm:
    """A context manager that does nothing when written to."""

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def write(self, data):
        pass


class NoEntryPointsSchemeDictionaryDestination(
    installer.destinations.SchemeDictionaryDestination
):
    """
    A custom destination that prevents the `installer` package from automatically
    generating scripts for `console_scripts` entry points.

    rules_python handles entry points via its own `venv_entry_point` targets.
    If `installer` also generates these scripts in the `bin/` directory, it
    causes a target naming collision because `whl_library_targets.bzl` will
    try to create a `venv_rewrite_shebang` target with the same name.

    By overriding `for_script` to return a no-op dummy writer, we silently
    discard the generated entry point scripts while still allowing `installer`
    to process the rest of the wheel normally (including `.data/scripts` which
    we do want to keep).
    """

    def for_script(self, name, module, attribute):
        return DoNothingCm()


class Wheel:
    """Representation of the compressed .whl file"""

    def __init__(self, path: Path):
        self._path = path

    @property
    def path(self) -> Path:
        return self._path

    @property
    def metadata(self) -> email.message.Message:
        with installer.sources.WheelFile.open(self.path) as wheel_source:
            metadata_contents = wheel_source.read_dist_info("METADATA")
            metadata = installer.utils.parse_metadata_file(metadata_contents)
        return metadata

    @property
    def version(self) -> str:
        # TODO Also available as installer.sources.WheelSource.version
        return str(self.metadata["Version"])

    def unzip(self, directory: str) -> None:
        installation_schemes = {
            "purelib": "/site-packages",
            "platlib": "/site-packages",
            "headers": "/include",
            "scripts": "/bin",
            "data": "/data",
        }

        destination = NoEntryPointsSchemeDictionaryDestination(
            installation_schemes,
            # TODO Should entry_point scripts also be handled by installer rather than custom code?
            interpreter="python",
            script_kind="posix",
            destdir=directory,
            bytecode_optimization_levels=[],
        )

        with installer.sources.WheelFile.open(self.path) as wheel_source:
            installer.install(
                source=wheel_source,
                destination=destination,
                additional_metadata={
                    "INSTALLER": b"https://github.com/bazel-contrib/rules_python",
                },
            )
