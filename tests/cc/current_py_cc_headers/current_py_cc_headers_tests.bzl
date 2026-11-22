# Copyright 2023 The Bazel Authors. All rights reserved.
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

"""Tests for current_py_cc_headers."""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_shared_library.bzl", "cc_shared_library")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load("//python/cc:py_cc_toolchain.bzl", "py_cc_toolchain")
load("//tests/support:cc_info_subject.bzl", "cc_info_subject")
load("//tests/support:support.bzl", "CC_TOOLCHAIN")

_tests = []

def _verify_headers_target(env, target):
    # Check that the forwarded CcInfo looks vaguely correct.
    compilation_context = env.expect.that_target(target).provider(
        CcInfo,
        factory = cc_info_subject,
    ).compilation_context()
    compilation_context.direct_headers().contains_exactly(
        env.ctx.files.header_files,
    )
    compilation_context.direct_public_headers().contains_exactly(
        env.ctx.files.header_files,
    )

    # NOTE: Bazel 8 and lower put cc_library.includes into `.system_includes`,
    # while Bazel 9 put it in `.includes`. Both result in the includes being
    # added as system includes, so either is acceptable for the expected
    # `#include <Python.h>` to work.
    includes = compilation_context.actual.includes.to_list() + compilation_context.actual.system_includes.to_list()

    # NOTE: The include dir gets added twice, once for the source path,
    # and once for the config-specific path.
    env.expect.that_collection(includes).contains_at_least_predicates([
        matching.str_matches("*/py_include"),
    ])

    # Check that the forward DefaultInfo looks correct
    env.expect.that_target(target).runfiles().contains_predicate(
        matching.str_matches("*/cc_toolchains/data.txt"),
    )

def _test_current_toolchain_headers(name):
    analysis_test(
        name = name,
        impl = _test_current_toolchain_headers_impl,
        target = "//python/cc:current_py_cc_headers",
        config_settings = {
            "//command_line_option:extra_toolchains": [CC_TOOLCHAIN],
        },
        attrs = {
            "header_files": attr.label_list(
                default = [
                    "//tests/support/cc_toolchains:py_headers_files",
                ],
                allow_files = True,
            ),
        },
    )

def _test_current_toolchain_headers_impl(env, target):
    _verify_headers_target(env, target)

_tests.append(_test_current_toolchain_headers)

def _test_toolchain_is_registered_by_default(name):
    analysis_test(
        name = name,
        impl = _test_toolchain_is_registered_by_default_impl,
        target = "//python/cc:current_py_cc_headers",
    )

def _test_toolchain_is_registered_by_default_impl(env, target):
    env.expect.that_target(target).has_provider(CcInfo)

_tests.append(_test_toolchain_is_registered_by_default)

def _test_current_toolchain_headers_abi3(name):
    analysis_test(
        name = name,
        impl = _test_current_toolchain_headers_abi3_impl,
        target = "//python/cc:current_py_cc_headers_abi3",
        config_settings = {
            "//command_line_option:extra_toolchains": [CC_TOOLCHAIN],
        },
        attrs = {
            "header_files": attr.label_list(
                default = [
                    "//tests/support/cc_toolchains:py_headers_abi3_files",
                ],
                allow_files = True,
            ),
        },
    )

def _test_current_toolchain_headers_abi3_impl(env, target):
    _verify_headers_target(env, target)

_tests.append(_test_current_toolchain_headers_abi3)

# On Windows the headers targets carry the Python import libraries. Check that
# they are still linked into a cc_binary with dynamic_deps.
def _setup_binary_with_dynamic_deps(name, headers_target):
    util.helper_target(
        cc_library,
        name = name + ".python_lib",
        srcs = ["python_lib.c"],
    )
    util.helper_target(
        py_cc_toolchain,
        name = name + ".py_cc_toolchain",
        headers = ":" + name + ".python_lib",
        headers_abi3 = ":" + name + ".python_lib",
        python_version = "3.999",
    )
    util.helper_target(
        native.toolchain,
        name = name + ".toolchain",
        toolchain = ":" + name + ".py_cc_toolchain",
        toolchain_type = "//python/cc:toolchain_type",
    )
    util.helper_target(
        cc_library,
        name = name + ".dep",
        srcs = ["python_lib.c"],
    )
    util.helper_target(
        cc_shared_library,
        name = name + ".dep_shared",
        deps = [":" + name + ".dep"],
    )
    util.helper_target(
        cc_binary,
        name = name + ".bin",
        linkshared = True,
        dynamic_deps = [":" + name + ".dep_shared"],
        deps = [
            ":" + name + ".dep",
            headers_target,
        ],
    )
    analysis_test(
        name = name,
        impl = _test_binary_with_dynamic_deps_impl,
        target = name + ".bin",
        config_settings = {
            # This transition replaces the C++ toolchain supplied by RBE.
            "//command_line_option:extra_toolchains": [
                str(native.package_relative_label(":" + name + ".toolchain")),
                str(Label("//tests/support/cc_toolchains:linux_toolchain_definition")),
                str(Label("//tests/support/cc_toolchains:mac_toolchain_definition")),
                str(Label("//tests/support/cc_toolchains:windows_toolchain_definition")),
            ],
        },
    )

def _test_binary_with_dynamic_deps_impl(env, target):
    test_name = target.label.name.removesuffix(".bin")
    link_inputs = env.expect.that_target(target).action_named("CppLink").inputs()
    link_inputs.contains_predicate(
        matching.file_basename_contains(test_name + ".python_lib"),
    )

    # :dep is linked through :dep_shared, not statically.
    link_inputs.not_contains_predicate(
        matching.file_basename_contains(test_name + ".dep."),
    )

def _test_headers_binary_with_dynamic_deps(name):
    _setup_binary_with_dynamic_deps(name, "//python/cc:current_py_cc_headers")

_tests.append(_test_headers_binary_with_dynamic_deps)

def _test_headers_abi3_binary_with_dynamic_deps(name):
    _setup_binary_with_dynamic_deps(name, "//python/cc:current_py_cc_headers_abi3")

_tests.append(_test_headers_abi3_binary_with_dynamic_deps)

def current_py_cc_headers_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
