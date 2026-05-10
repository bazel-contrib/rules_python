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

"Tests for coverage_url_sha256 lookups against the bundled wheel set."

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:coverage_deps.bzl", "coverage_url_sha256")  # buildifier: disable=bzl-visibility

_tests = []

def _test_supported_version_and_platform_returns_url_and_sha(env):
    result = coverage_url_sha256("3.10", "aarch64-apple-darwin")
    env.expect.that_bool(result != None).equals(True)
    url, sha256 = result
    env.expect.that_str(url).contains("coverage-")
    env.expect.that_str(url).contains("cp310")
    env.expect.that_str(url).contains("macosx_11_0_arm64")
    env.expect.that_int(len(sha256)).equals(64)

_tests.append(_test_supported_version_and_platform_returns_url_and_sha)

def _test_cp314_is_in_bundled_set(env):
    # Regression guard: cp314 was the motivation for adding the warning.
    # If a future regen accidentally drops it, this test fires.
    result = coverage_url_sha256("3.14", "aarch64-apple-darwin")
    env.expect.that_bool(result != None).equals(True)
    url, _ = result
    env.expect.that_str(url).contains("cp314")

_tests.append(_test_cp314_is_in_bundled_set)

def _test_freethreaded_variant_is_in_bundled_set(env):
    # Regression guard: freethreaded variants for cp313+ are part of the
    # bundled set; ensure regen does not drop them.
    result = coverage_url_sha256("3.14", "aarch64-apple-darwin-freethreaded")
    env.expect.that_bool(result != None).equals(True)
    url, _ = result
    env.expect.that_str(url).contains("cp314t")

_tests.append(_test_freethreaded_variant_is_in_bundled_set)

def _test_unsupported_version_returns_none(env):
    # Python 3.7 is not in the bundled wheel set (and is far below the
    # current floor). This is the path that triggers the warning in
    # coverage_dep.
    result = coverage_url_sha256("3.7", "aarch64-apple-darwin")
    env.expect.that_bool(result == None).equals(True)

_tests.append(_test_unsupported_version_returns_none)

def _test_windows_returns_none(env):
    # Windows is intentionally not supported by the bundled coverage tool;
    # the lookup must return None so the caller can keep the windows
    # branch silent.
    result = coverage_url_sha256("3.10", "x86_64-pc-windows-msvc")
    env.expect.that_bool(result == None).equals(True)

_tests.append(_test_windows_returns_none)

def coverage_deps_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
