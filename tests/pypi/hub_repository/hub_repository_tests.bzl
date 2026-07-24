# Copyright 2026 The Bazel Authors. All rights reserved.
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

"""hub_repository tests"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load(
    "//python/private/pypi:hub_repository.bzl",
    "render_hub_build_file",
)  # buildifier: disable=bzl-visibility

_tests = []

def _test_build_file_without_lock_target(env):
    actual = render_hub_build_file()

    env.expect.that_str(actual).equals("""\
package(default_visibility = ["//visibility:public"])

# Ensure the `requirements.bzl` source can be accessed by stardoc, since users
# load() from it.
exports_files(["requirements.bzl"])
""")

_tests.append(_test_build_file_without_lock_target)

def _test_build_file_with_lock_target(env):
    actual = render_hub_build_file(
        lock_targets = [
            {
                "name": "lock",
                "out": "requirements_lock.txt",
                "python_version": "3.13",
                "srcs": ["@@//:requirements.in"],
            },
        ],
    )

    env.expect.that_str(actual).equals("""\
load("@rules_python//python/uv:lock.bzl", "lock")

package(default_visibility = ["//visibility:public"])

# Ensure the `requirements.bzl` source can be accessed by stardoc, since users
# load() from it.
exports_files(["requirements.bzl"])

lock(
    name = "lock",
    out = "requirements_lock.txt",
    python_version = "3.13",
    srcs = ["@@//:requirements.in"],
    visibility = ["//visibility:public"],
)
""")

_tests.append(_test_build_file_with_lock_target)

def hub_repository_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )
