# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Starlark tests for py_runtime rule."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load(
    "//python/private:toolchain_types.bzl",
    "EXEC_TOOLS_TOOLCHAIN_TYPE",
    "PY_CC_TOOLCHAIN_TYPE",
    "TARGET_TOOLCHAIN_TYPE",
)  # buildifier: disable=bzl-visibility
load("//tests/support:support.bzl", "EXEC_TOOLS_TOOLCHAIN")

_LookupInfo = provider()  # buildifier: disable=provider-params

def _use_toolchains_impl(ctx):
    return [
        _LookupInfo(
            target = ctx.toolchains[TARGET_TOOLCHAIN_TYPE],
            exec = ctx.toolchains[EXEC_TOOLS_TOOLCHAIN_TYPE],
            cc = ctx.toolchains[PY_CC_TOOLCHAIN_TYPE],
        ),
    ]

_use_toolchains = rule(
    implementation = _use_toolchains_impl,
    toolchains = [
        TARGET_TOOLCHAIN_TYPE,
        EXEC_TOOLS_TOOLCHAIN_TYPE,
        PY_CC_TOOLCHAIN_TYPE,
    ],
)

_tests = []

def _test_runtime_env_toolchain_matches(name):
    rt_util.helper_target(
        _use_toolchains,
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = _test_runtime_env_toolchain_matches_impl,
        target = name + "_subject",
        config_settings = {
            "//command_line_option:extra_toolchains": [
                str(Label("//python/runtime_env_toolchains:all")),
            ],
            EXEC_TOOLS_TOOLCHAIN: "enabled",
            str(Label("//python/private:visible_for_testing")): True,
        },
    )

def _test_runtime_env_toolchain_matches_impl(env, target):
    env.expect.that_str(
        str(target[_LookupInfo].target.toolchain_label),
    ).contains("runtime_env_py_runtime_pair")
    env.expect.that_str(
        str(target[_LookupInfo].exec.toolchain_label),
    ).contains("runtime_env_py_exec_tools")
    env.expect.that_str(
        str(target[_LookupInfo].cc.toolchain_label),
    ).contains("runtime_env_py_cc")

_tests.append(_test_runtime_env_toolchain_matches)

def runtime_env_toolchain_test_suite(name):
    test_suite(name = name, tests = _tests)
