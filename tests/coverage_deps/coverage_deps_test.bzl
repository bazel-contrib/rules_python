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

"Tests for the warning emitted by coverage_dep when no wheel is available."

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:coverage_deps.bzl", "coverage_dep")  # buildifier: disable=bzl-visibility
load("//python/private:repo_utils.bzl", "REPO_DEBUG_ENV_VAR", "REPO_VERBOSITY_ENV_VAR", "repo_utils")  # buildifier: disable=bzl-visibility

_tests = []

def _capturing_logger():
    """Build a (logger, captured_messages_list) pair.

    The logger has its verbosity set to INFO so WARN messages are captured but
    nothing noisier than necessary is emitted. The printer collects the second
    positional argument from each printer invocation (the formatted message).
    """
    captured = []
    logger = repo_utils.logger(
        struct(
            getenv = {
                REPO_DEBUG_ENV_VAR: None,
                REPO_VERBOSITY_ENV_VAR: "INFO",
            }.get,
        ),
        name = "unit-test",
        printer = lambda _key, message: captured.append(message),
    )
    return logger, captured

def _test_unsupported_python_version_warns(env):
    # cp37 is not in the bundled wheel set; coverage_dep should return None
    # and emit a warning describing the misconfiguration.
    logger, captured = _capturing_logger()
    result = coverage_dep(
        name = "unused_for_test",
        python_version = "3.7",
        platform = "aarch64-apple-darwin",
        visibility = ["//visibility:public"],
        logger = logger,
    )
    env.expect.that_bool(result == None).equals(True)
    env.expect.that_int(len(captured)).equals(1)
    env.expect.that_str(captured[0]).contains("no wheel for")
    env.expect.that_str(captured[0]).contains("python_version=3.7")
    env.expect.that_str(captured[0]).contains("platform=aarch64-apple-darwin")

_tests.append(_test_unsupported_python_version_warns)

def _test_windows_platform_is_silent(env):
    # Windows is intentionally unsupported and not actionable; coverage_dep
    # must return None without logging anything.
    logger, captured = _capturing_logger()
    result = coverage_dep(
        name = "unused_for_test",
        python_version = "3.10",
        platform = "x86_64-pc-windows-msvc",
        visibility = ["//visibility:public"],
        logger = logger,
    )
    env.expect.that_bool(result == None).equals(True)
    env.expect.that_int(len(captured)).equals(0)

_tests.append(_test_windows_platform_is_silent)

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
