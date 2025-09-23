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
load("@rules_testing//lib:truth.bzl", "matching")
load("//python/private:py_info.bzl", "PyInfo")

_tests = []

def _test_static_deps_impl(env, target):
    py_info = env.expect.that_target(target).has_provider(PyInfo)
    cc_info = env.expect.that_target(target).has_provider(CcInfo)

    # The .so should be in PyInfo
    env.expect.that_collection(py_info.transitive_sources).has_size(1)
    env.expect.that_collection(py_info.transitive_sources).contains_predicate(
        matching.str_matches("ext_static.so$"),
    )

    # CcInfo from static_deps should not be propagated.
    env.expect.that_collection(cc_info.linking_context.linker_inputs.to_list()).is_empty()

def _test_static_deps(name):
    analysis_test(
        name = name,
        impl = _test_static_deps_impl,
        target = "//tests/cc/py_extension:ext_static",
    )

_tests.append(_test_static_deps)

def _test_dynamic_deps_impl(env, target):
    py_info = env.expect.that_target(target).has_provider(PyInfo)
    cc_info = env.expect.that_target(target).has_provider(CcInfo)

    # The .so should be in PyInfo
    env.expect.that_collection(py_info.transitive_sources).has_size(1)
    env.expect.that_collection(py_info.transitive_sources).contains_predicate(
        matching.str_matches("ext_dynamic.so$"),
    )

    # CcInfo from dynamic_deps should be propagated.
    env.expect.that_collection(cc_info.linking_context.linker_inputs.to_list()).is_not_empty()

def _test_dynamic_deps(name):
    analysis_test(
        name = name,
        impl = _test_dynamic_deps_impl,
        target = "//tests/cc/py_extension:ext_dynamic",
    )

_tests.append(_test_dynamic_deps)

def py_extension_analysis_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
