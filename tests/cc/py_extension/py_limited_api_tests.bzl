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

def _test_limited_pass_impl(env, target):
    env.expect.that_target(target).default_outputs().contains(
        "tests/cc/py_extension/{}.abi3.so".format(target.label.name)
    )

def _test_limited_same_version(name):
    util.helper_target(
        cc_library,
        name = name + '_csl',
        defines = ["Py_LIMITED_API=0x03080000"],
        deps = [
            "@rules_python//python/cc:current_py_cc_headers",
        ],
    )
    py_extension(
        name = name + '_pyext',
        static_deps = [':' + name + '_csl'],
        py_limited_api = '3.8',
    )
    analysis_test(
        name = name,
        target = name + "_pyext",
        impl = _test_limited_pass_impl,
    )

def _test_limited_older_dep(name):
    util.helper_target(
        cc_library,
        name = name + '_csl',
        defines = ["Py_LIMITED_API=0x03080000"], # 3.8
        deps = [
            "@rules_python//python/cc:current_py_cc_headers",
        ],
    )
    py_extension(
        name = name + '_pyext',
        static_deps = [':' + name + '_csl'],
        py_limited_api = '3.9', # 3.9
    )
    analysis_test(
        name = name,
        target = name + "_pyext",
        impl = _test_limited_pass_impl,
    )

def _test_limited_newer_dep(name):
    util.helper_target(
        cc_library,
        name = name + '_csl',
        defines = ["Py_LIMITED_API=0x03090000"], # 3.9
        deps = [
            "@rules_python//python/cc:current_py_cc_headers",
        ],
    )
    py_extension(
        name = name + '_pyext',
        static_deps = [':' + name + '_csl'],
        py_limited_api = '3.8', # 3.8
    )
    analysis_test(
        name = name,
        target = name + "_pyext",
        impl = _test_limited_newer_dep_impl,
        expect_failure = True,
    )

def _test_limited_newer_dep_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*Incompatible Python Limited API targets detected*"),
    )

def _test_limited_dep_missing_define(name):
    util.helper_target(
        cc_library,
        name = name + '_csl',
        deps = [
            "@rules_python//python/cc:current_py_cc_headers",
        ],
    )
    py_extension(
        name = name + '_pyext',
        static_deps = [':' + name + '_csl'],
        py_limited_api = '3.8',
    )
    analysis_test(
        name = name,
        target = name + "_pyext",
        impl = _test_limited_dep_missing_define_impl,
        expect_failure = True,
    )

def _test_limited_dep_missing_define_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*Unsafe Python C API usage in dependency*"),
    )

def _test_limited_dep_unspecified_define(name):
    util.helper_target(
        cc_library,
        name = name + '_csl',
        defines = ["Py_LIMITED_API"],
        deps = [
            "@rules_python//python/cc:current_py_cc_headers",
        ],
    )
    py_extension(
        name = name + '_pyext',
        static_deps = [':' + name + '_csl'],
        py_limited_api = '3.8',
    )
    analysis_test(
        name = name,
        target = name + "_pyext",
        impl = _test_limited_dep_unspecified_define_impl,
        expect_failure = True,
    )

def _test_limited_dep_unspecified_define_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*Unsafe Python Limited API definition in dependency*"),
    )

def _test_no_limited_api(name):
    util.helper_target(
        cc_library,
        name = name + '_csl',
        deps = [
            "@rules_python//python/cc:current_py_cc_headers",
        ],
    )
    py_extension(
        name = name + '_pyext',
        static_deps = [':' + name + '_csl'],
    )
    analysis_test(
        name = name,
        target = name + "_pyext",
        impl = _test_no_limited_api_impl,
    )

def _test_no_limited_api_impl(env, target):
    # Should pass, nothing to assert on filename since it is platform-specific
    pass

def _test_no_limited_api_dep_has_limited(name):
    util.helper_target(
        cc_library,
        name = name + '_csl',
        defines = ["Py_LIMITED_API=0x03080000"],
        deps = [
            "@rules_python//python/cc:current_py_cc_headers",
        ],
    )
    py_extension(
        name = name + '_pyext',
        static_deps = [':' + name + '_csl'],
    )
    analysis_test(
        name = name,
        target = name + "_pyext",
        impl = _test_no_limited_api_dep_has_limited_impl,
    )

def _test_no_limited_api_dep_has_limited_impl(env, target):
    pass

def _test_limited_api_dep_has_no_python(name):
    util.helper_target(
        cc_library,
        name = name + '_csl',
    )
    py_extension(
        name = name + '_pyext',
        static_deps = [':' + name + '_csl'],
        py_limited_api = '3.8',
    )
    analysis_test(
        name = name,
        target = name + "_pyext",
        impl = _test_limited_pass_impl,
    )

def _test_invalid_version_format(name):
    util.helper_target(
        cc_library,
        name = name + '_csl',
        defines = ["Py_LIMITED_API=0x03080000"],
        deps = [
            "@rules_python//python/cc:current_py_cc_headers",
        ],
    )
    py_extension(
        name = name + '_pyext',
        static_deps = [':' + name + '_csl'],
        py_limited_api = '3.8.1',
    )
    analysis_test(
        name = name,
        target = name + "_pyext",
        impl = _test_invalid_version_format_impl,
        expect_failure = True,
    )

def _test_invalid_version_format_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*Invalid py_limited_api version*"),
    )

def py_limited_api_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_limited_same_version,
            _test_limited_older_dep,
            _test_limited_newer_dep,
            _test_limited_dep_missing_define,
            _test_limited_dep_unspecified_define,
            _test_no_limited_api,
            _test_no_limited_api_dep_has_limited,
            _test_limited_api_dep_has_no_python,
            _test_invalid_version_format,
        ],
    )
