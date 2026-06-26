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

"""Tests for the py_limited_api attribute for py_extension."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("//python/cc:py_extension.bzl", "py_extension")
load("@rules_cc//cc:cc_library.bzl", "cc_library")


def _test_limited_same_version(name):
    # given
    util.helper_target(
        cc_library,
        name = name + '_csl',
        defines = ["Py_LIMITED_API=0x3080000"],
        deps = [
            "@rules_python//python/cc:current_py_cc_headers",
        ],
    )
    py_extension(
        name = name + '_pyext',
        static_deps = [':' + name + '_csl'],
        py_limited_api = '3.8',
    )

    # when
    analysis_test(
        name = name,
        target = name + "_pyext",
        impl=_test_limited_same_version_impl)

def _test_limited_same_version_impl(env, target):
    # then
    env.expect.that_target(target).default_outputs().contains(
        "tests/cc/py_extension/test_limited_same_version_pyext.abi3.so"
    )

# test cases:
# py_limited_api
#   - 3.8 -> 3.9
#   - 3.9 -> 3.8
#   - 3.9 -> 3.9    ok
#   - none -> 3.8
#   - 3.8 -> none   fail
#   - 3.8 -> nopy   ok
#   - none -> none  ok?
#   - none -> nopy  ok?
# invalid values for version string
#   - 2.x
#   - 3.0 and 3.1
#   - 4.x
#   - not version string, e.g. "asdf"
#   - patch versions? 3.8.4 ?
#   - empty string or null?


def py_limited_api_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_limited_same_version,
        ],
    )
