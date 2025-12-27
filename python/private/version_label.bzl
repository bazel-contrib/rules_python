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

""

load(":version.bzl", v = "version")

def version_label(version, *, sep = ""):
    """A version fragment derived from python minor version.

    This replaces dots with the provided separator.

    Examples:
        version_label("3.9") == "39"
        version_label("3.9.12", sep="_") == "3_9_12"
        version_label("3.11") == "311"
        version_label("3.11.12") == "31112"

    Args:
        version: Python version.
        sep: The separator between major and minor version numbers, defaults
            to an empty string.

    Returns:
        The fragment of the version.
    """
    parsed = v.parse(version)
    return parsed.string.replace(".", sep)
