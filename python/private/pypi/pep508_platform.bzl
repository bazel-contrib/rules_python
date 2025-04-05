# Copyright 2025 The Bazel Authors. All rights reserved.
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

"""The platform abstraction
"""

def platform(*, abi = None, os = None, arch = None):
    """platform returns a struct for the platform.

    Args:
        abi: {type}`str | None` the target ABI, e.g. `"cp39"`.
        os: {type}`str | None` the target os, e.g. `"linux"`.
        arch: {type}`str | None` the target CPU, e.g. `"aarch64"`.

    Returns:
        A struct.
    """

    # Note, this is used a lot as a key in dictionaries, so it cannot contain
    # methods.
    return struct(
        abi = abi,
        os = os,
        arch = arch,
    )

def platform_from_str(p, python_version):
    """Return a platform from a string.

    Args:
        p: {type}`str` the actual string.
        python_version: {type}`str` the python version to add to platform if needed.

    Returns:
        A struct that is returned by the `_platform` function.
    """
    if p.startswith("cp"):
        abi, _, p = p.partition("_")
    elif python_version:
        major, _, tail = python_version.partition(".")
        abi = "cp{}{}".format(major, tail)
    else:
        abi = None

    os, _, arch = p.partition("_")
    return platform(abi = abi, os = os or None, arch = arch or None)
