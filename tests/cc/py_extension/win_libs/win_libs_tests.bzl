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

"""Tests for the CPython import library that py_extension links on Windows."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("//python/cc:py_extension.bzl", "py_extension")
load("//tests/support:support.bzl", "CC_TOOLCHAIN")

# The Windows py_cc_toolchain goes last, since later extra_toolchains win:
# the one in CC_TOOLCHAIN has no target constraints.
_CONFIG_SETTINGS = {
    "//command_line_option:extra_toolchains": [
        CC_TOOLCHAIN,
        str(Label("//tests/support/cc_toolchains:fake_py_cc_toolchain_windows")),
    ],
    "//command_line_option:platforms": [str(Label("//tests/support/platforms:windows_x86_64"))],
}

def _test_limited_api(name):
    py_extension(
        name = name + "_pyext",
        py_limited_api = "3.8",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = "_" + name + "_pyext_win_libs",
        impl = _test_limited_api_impl,
        config_settings = _CONFIG_SETTINGS,
    )

def _test_limited_api_impl(env, target):
    env.expect.that_collection(
        [f.basename for f in target[DefaultInfo].files.to_list()],
    ).contains_exactly(["python3.lib"])

def _test_no_limited_api(name):
    py_extension(
        name = name + "_pyext",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = "_" + name + "_pyext_win_libs",
        impl = _test_no_limited_api_impl,
        config_settings = _CONFIG_SETTINGS,
    )

def _test_no_limited_api_impl(env, target):
    env.expect.that_collection(
        [f.basename for f in target[DefaultInfo].files.to_list()],
    ).contains_exactly(["python312.lib"])

def win_libs_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _test_limited_api,
            _test_no_limited_api,
        ],
    )
