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

"Tests for coverage_dep and the coverage wheel selection."

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:coverage_deps.bzl", "coverage_dep", "select_coverage_whl")  # buildifier: disable=bzl-visibility

_tests = []

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

def _test_select_platform_whl(env):
    for python_version, platform, want in [
        ("3.9.18", "x86_64-unknown-linux-gnu", "coverage-7.10.7-cp39-cp39-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl"),
        ("3.10", "aarch64-unknown-linux-gnu", "coverage-7.10.7-cp310-cp310-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl"),
        ("3.12.4", "x86_64-apple-darwin", "coverage-7.10.7-cp312-cp312-macosx_10_13_x86_64.whl"),
        ("3.13.1", "aarch64-apple-darwin", "coverage-7.10.7-cp313-cp313-macosx_11_0_arm64.whl"),
        ("3.15.0", "x86_64-apple-darwin", "coverage-7.17.0-cp315-cp315-macosx_10_15_x86_64.whl"),
    ]:
        got = select_coverage_whl(python_version = python_version, platform = platform)
        env.expect.where(
            python_version = python_version,
            platform = platform,
        ).that_str(got.filename).equals(want)

_tests.append(_test_select_platform_whl)

def _test_select_freethreaded_whl(env):
    for python_version, platform, want in [
        ("3.13.1", "aarch64-apple-darwin-freethreaded", "coverage-7.10.7-cp313-cp313t-macosx_11_0_arm64.whl"),
        ("3.14.0", "x86_64-unknown-linux-gnu-freethreaded", "coverage-7.10.7-cp314-cp314t-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl"),
        ("3.15.0", "aarch64-unknown-linux-gnu-freethreaded", "coverage-7.17.0-cp315-cp315t-manylinux2014_aarch64.manylinux_2_17_aarch64.manylinux_2_28_aarch64.whl"),
    ]:
        got = select_coverage_whl(python_version = python_version, platform = platform)
        env.expect.where(
            python_version = python_version,
            platform = platform,
        ).that_str(got.filename).equals(want)

_tests.append(_test_select_freethreaded_whl)

def _test_select_fallback_whl(env):
    for python_version, platform in [
        # There are no freethreaded wheels for this version
        ("3.12.4", "x86_64-unknown-linux-gnu-freethreaded"),
        # Platforms without bundled platform specific wheels
        ("3.13.1", "riscv64-unknown-linux-gnu"),
        ("3.13.1", "x86_64-unknown-linux-musl"),
        # Python versions without bundled platform specific wheels
        ("3.16.0", "x86_64-unknown-linux-gnu"),
    ]:
        got = select_coverage_whl(python_version = python_version, platform = platform)
        env.expect.where(
            python_version = python_version,
            platform = platform,
        ).that_str(got.filename).equals("coverage-7.10.7-py3-none-any.whl")

_tests.append(_test_select_fallback_whl)

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
