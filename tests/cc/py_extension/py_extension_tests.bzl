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

"""Tests for py_extension."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("//python/private:py_info.bzl", "PyInfo")

_tests = []

def _test_basic_impl(env, target):
    env.expect.that_target(target).has_provider(PyInfo)
    env.expect.that_target(target).has_provider(CcInfo)

def _test_basic(name):
    analysis_test(
        name = name,
        impl = _test_basic_impl,
        target = "//tests/cc/py_extension:ext",
    )

_tests.append(_test_basic)

def py_extension_analysis_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
