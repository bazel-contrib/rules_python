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

load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("//python/cc:py_extension.bzl", "py_extension")
load("//python/private:py_info.bzl", "PyInfo")  # buildifier: disable=bzl-visibility

_tests = []

def _test_static_deps_impl(env, target):
    env.expect.that_target(target).has_provider(PyInfo)
    py_info = target[PyInfo]

    # The extension should be in PyInfo
    env.expect.that_collection(py_info.transitive_sources.to_list()).has_size(1)
    env.expect.that_depset_of_files(py_info.transitive_sources).contains_predicate(
        matching.file_path_matches("{}.*311-*".format(target.label.name)),
    )

def _test_static_deps(name):
    util.helper_target(
        cc_library,
        name = name + "_dep",
        srcs = ["//tests/cc/py_extension:static_dep.c"],
        hdrs = ["//tests/cc/py_extension:static_dep.h"],
    )
    util.helper_target(
        py_extension,
        name = name + "_subject",
        deps = [":" + name + "_dep"],
    )
    analysis_test(
        name = name,
        impl = _test_static_deps_impl,
        target = name + "_subject",
    )

_tests.append(_test_static_deps)

def _test_data_deps_impl(env, target):
    env.expect.that_target(target).has_provider(PyInfo)

    # Check that data file is in runfiles
    default_info = target[DefaultInfo]
    env.expect.that_depset_of_files(default_info.default_runfiles.files).contains_predicate(
        matching.file_basename_equals("some_data.txt"),
    )

def _test_data_deps(name):
    util.helper_target(
        cc_library,
        name = name + "_dep",
        srcs = ["//tests/cc/py_extension:static_dep.c"],
        hdrs = ["//tests/cc/py_extension:static_dep.h"],
    )
    util.helper_target(
        py_extension,
        name = name + "_subject",
        data = ["//tests/cc/py_extension:some_data.txt"],
        deps = [":" + name + "_dep"],
    )
    analysis_test(
        name = name,
        impl = _test_data_deps_impl,
        target = name + "_subject",
    )

_tests.append(_test_data_deps)

def _test_dynamic_deps_impl(env, target):
    env.expect.that_target(target).has_provider(PyInfo)
    py_info = target[PyInfo]

    # The extension should be in PyInfo
    env.expect.that_collection(py_info.transitive_sources.to_list()).has_size(1)
    env.expect.that_depset_of_files(py_info.transitive_sources).contains_predicate(
        matching.file_path_matches("{}.*311-*".format(target.label.name)),
    )

def _test_dynamic_deps(name):
    util.helper_target(
        cc_library,
        name = name + "_impl",
        srcs = ["//tests/cc/py_extension:ext_shared.c"],
        copts = [
            "-fPIC",
            "-fvisibility=hidden",
        ],
        deps = [
            "//tests/cc/py_extension:add_one_impl",
            "@rules_python//python/cc:current_py_cc_headers",
        ],
    )
    util.helper_target(
        py_extension,
        name = name + "_subject",
        dynamic_deps = [
            "//tests/cc/py_extension:add_one_shared",
        ],
        imports = ["."],
        deps = [
            ":" + name + "_impl",
        ],
    )
    analysis_test(
        name = name,
        impl = _test_dynamic_deps_impl,
        target = name + "_subject",
    )

_tests.append(_test_dynamic_deps)

def _test_musl_platform_impl(env, target):
    env.expect.that_target(target).has_provider(PyInfo)
    py_info = target[PyInfo]
    env.expect.that_depset_of_files(py_info.transitive_sources).contains_predicate(
        matching.file_path_matches("{}.*311-*".format(target.label.name)),
    )

def _test_musl_platform(name):
    util.helper_target(
        cc_library,
        name = name + "_dep",
        srcs = ["//tests/cc/py_extension:static_dep.c"],
        hdrs = ["//tests/cc/py_extension:static_dep.h"],
    )
    util.helper_target(
        py_extension,
        name = name + "_subject",
        deps = [":" + name + "_dep"],
    )
    analysis_test(
        name = name,
        impl = _test_musl_platform_impl,
        target = name + "_subject",
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
