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
    env.expect.that_target(target).has_provider(PyInfo)
    py_info = target[PyInfo]
    env.expect.that_target(target).has_provider(CcInfo)
    cc_info = target[CcInfo]

    # The .so should be in PyInfo
    env.expect.that_collection(py_info.transitive_sources.to_list()).has_size(1)
    env.expect.that_depset_of_files(py_info.transitive_sources).contains_predicate(
        matching.file_basename_equals("ext_static.cpython-311-x86_64-linux-gnu.so"),
    )

    # CcInfo from static_deps should not be propagated.
    env.expect.that_depset_of_files(cc_info.linking_context.linker_inputs).contains_exactly([])

def _test_static_deps(name):
    analysis_test(
        name = name,
        impl = _test_static_deps_impl,
        target = "//tests/cc/py_extension:ext_static",
    )

_tests.append(_test_static_deps)

def _test_dynamic_deps_impl(env, target):
    env.expect.that_target(target).has_provider(PyInfo)
    py_info = target[PyInfo]
    env.expect.that_target(target).has_provider(CcInfo)
    cc_info = target[CcInfo]

    # The .so should be in PyInfo
    env.expect.that_collection(py_info.transitive_sources.to_list()).has_size(1)
    env.expect.that_depset_of_files(py_info.transitive_sources).contains_predicate(
        matching.file_basename_equals("ext_shared.cpython-311-x86_64-linux-gnu.so"),
    )

    # CcInfo from dynamic_deps should be propagated.
    env.expect.that_collection(cc_info.linking_context.linker_inputs.to_list()).has_size(1)

def _test_dynamic_deps(name):
    analysis_test(
        name = name,
        impl = _test_dynamic_deps_impl,
        target = "//tests/cc/py_extension:ext_shared",
    )

_tests.append(_test_dynamic_deps)

def _test_musl_platform_impl(env, target):
    env.expect.that_target(target).has_provider(PyInfo)
    py_info = target[PyInfo]
    env.expect.that_depset_of_files(py_info.transitive_sources).contains_predicate(
        matching.file_basename_equals("ext_static.cpython-311-x86_64-linux-musl.so"),
    )

def _test_musl_platform(name):
    analysis_test(
        name = name,
        impl = _test_musl_platform_impl,
        target = "//tests/cc/py_extension:ext_static",
        config_settings = {
            str(Label("//python/config_settings:py_linux_libc")): "musl",
        },
    )

_tests.append(_test_musl_platform)

def py_extension_analysis_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
