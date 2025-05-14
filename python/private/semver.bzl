# Copyright 2024 The Bazel Authors. All rights reserved.
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

"A semver version parser"

load(":version.bzl", "version")

def _to_dict(self):
    return {
        "build": self.build,
        "major": self.major,
        "minor": self.minor,
        "patch": self.patch,
        "pre_release": self.pre_release,
    }

def _new(*, major, minor, patch, pre_release, build, ver = None):
    # buildifier: disable=uninitialized
    self = struct(
        major = int(major),
        minor = None if minor == None else int(minor),
        # NOTE: this is called `micro` in the Python interpreter versioning scheme
        patch = None if patch == None else int(patch),
        pre_release = pre_release,
        build = build,
        # buildifier: disable=uninitialized
        key = lambda: version.key(ver),
        str = lambda: ver.string,
        to_dict = lambda: _to_dict(self),
    )
    return self

def semver(version_str):
    """Parse the semver version and return the values as a struct.

    Args:
        version_str: {type}`str` the version string.

    Returns:
        A {type}`struct` with `major`, `minor`, `patch` and `build` attributes.
    """

    # Shim the version
    ver = version.parse(version_str, strict = True)
    major = ver.release[0]
    minor = ver.release[1] if len(ver.release) > 1 else None
    patch = ver.release[2] if len(ver.release) > 2 else None
    build = ver.local
    pre_release = ver.pre

    return _new(
        major = major,
        minor = minor,
        patch = patch,
        build = build,
        pre_release = pre_release,
        ver = ver,
    )
