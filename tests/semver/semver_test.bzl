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

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:semver.bzl", "semver")  # buildifier: disable=bzl-visibility

_tests = []

def _test_semver_from_major(env):
    actual = semver("3")
    env.expect.that_int(actual.major).equals(3)
    env.expect.that_int(actual.minor).equals(None)
    env.expect.that_int(actual.patch).equals(None)
    env.expect.that_str(actual.build).equals(None)

_tests.append(_test_semver_from_major)

def _test_semver_from_major_minor_version(env):
    actual = semver("4.9")
    env.expect.that_int(actual.major).equals(4)
    env.expect.that_int(actual.minor).equals(9)
    env.expect.that_int(actual.patch).equals(None)
    env.expect.that_str(actual.build).equals(None)

_tests.append(_test_semver_from_major_minor_version)

def _test_semver_with_build_info(env):
    actual = semver("1.2.3+mybuild")
    env.expect.that_int(actual.major).equals(1)
    env.expect.that_int(actual.minor).equals(2)
    env.expect.that_int(actual.patch).equals(3)
    env.expect.that_str(actual.build[0]).equals("mybuild")

_tests.append(_test_semver_with_build_info)

def _test_semver_with_build_info_multiple_pluses(env):
    actual = semver("1.2.3-rc0+buildinfo")
    env.expect.that_int(actual.major).equals(1)
    env.expect.that_int(actual.minor).equals(2)
    env.expect.that_int(actual.patch).equals(3)
    env.expect.that_str(actual.pre_release[0]).equals("rc")
    env.expect.that_int(actual.pre_release[1]).equals(0)

    # We normalize with PEP440
    env.expect.that_str(actual.build[0]).equals("buildinfo")

_tests.append(_test_semver_with_build_info_multiple_pluses)

def _test_semver_sort(_):
    _ = [
        semver(item)
        for item in [
            # The items are sorted from lowest to highest version
            "0.0.1",
            "0.1.0-rc",
            "0.1.0",
            "0.9.11",
            "0.9.12",
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0-rc.2",
            "1.0.0",
            # Also handle missing minor and patch version strings
            "2.0",
            "3",
            # Alphabetic comparison for different builds
            "3.0.0+build0",
            "3.0.0+build1",
        ]
    ]

_tests.append(_test_semver_sort)

def semver_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
