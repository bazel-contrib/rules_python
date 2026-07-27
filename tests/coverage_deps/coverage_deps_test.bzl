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

"Tests for coverage_dep's handling of platforms with no bundled wheel."

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:coverage_deps.bzl", "coverage_dep")  # buildifier: disable=bzl-visibility

_tests = []

def _test_unsupported_python_version_returns_none(env):
    # cp37 is not in the bundled wheel set, so there is no coverage tool to
    # attach to the runtime. Reporting that is py_runtime's job -- registration
    # covers every platform in PLATFORMS, most of which are never selected.
    result = coverage_dep(
        name = "unused_for_test",
        python_version = "3.7",
        platform = "aarch64-apple-darwin",
        visibility = ["//visibility:public"],
    )
    env.expect.that_bool(result == None).equals(True)

_tests.append(_test_unsupported_python_version_returns_none)

def _test_windows_platform_returns_none(env):
    # Windows is intentionally unsupported: the upstream coverage wrapper is
    # written in shell.
    result = coverage_dep(
        name = "unused_for_test",
        python_version = "3.10",
        platform = "x86_64-pc-windows-msvc",
        visibility = ["//visibility:public"],
    )
    env.expect.that_bool(result == None).equals(True)

_tests.append(_test_windows_platform_returns_none)

# NOTE: there is intentionally no unit test for the supported-wheel path
# (where coverage_dep returns a non-None label and emits no warning).
# That path calls `maybe(http_archive, ...)`, which calls
# `native.existing_rule()`. `native.existing_rule()` is only valid during
# BUILD file, legacy macro, or rule finalizer evaluation -- not during
# rule analysis, which is the phase rules_testing analysis tests run in.
# Calling coverage_dep with supported args from here therefore fails with
# "existing_rule() can only be used while evaluating a BUILD file, ...".
# The supported-wheel path is exercised end-to-end by `bazel coverage`
# against a real py_test target during ordinary use of the toolchain.

def coverage_deps_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite.
    """
    test_suite(name = name, basic_tests = _tests)
