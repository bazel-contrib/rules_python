# Copyright 2022 The Bazel Authors. All rights reserved.
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

""

load("@pythons_hub//:versions.bzl", "DEFAULT_PYTHON_VERSION", "MINOR_MAPPING")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:versions.bzl", "PLATFORMS", "TOOL_VERSIONS")
load("//python/private:bzlmod_enabled.bzl", "BZLMOD_ENABLED")  # buildifier: disable=bzl-visibility
load("//python/private:full_version.bzl", "full_version")  # buildifier: disable=bzl-visibility
load("//python/private:toolchain_types.bzl", "EXEC_TOOLS_TOOLCHAIN_TYPE")  # buildifier: disable=bzl-visibility
load("//tests/support:sh_py_run_test.bzl", "py_reconfig_test")
load("//tests/support:support.bzl", "PYTHON_VERSION")

_analysis_tests = []

def _transition_impl(input_settings, attr):
    settings = {
        PYTHON_VERSION: input_settings[PYTHON_VERSION],
    }
    if attr.python_version:
        settings[PYTHON_VERSION] = attr.python_version
    return settings

_python_version_transition = transition(
    implementation = _transition_impl,
    inputs = [PYTHON_VERSION],
    outputs = [PYTHON_VERSION],
)

TestInfo = provider(
    doc = "",
    fields = {
        "got": "",
        "want": "",
    },
)

def _lock_impl(ctx):
    exec_tools = ctx.toolchains[EXEC_TOOLS_TOOLCHAIN_TYPE].exec_tools
    got_version = exec_tools.exec_interpreter[platform_common.ToolchainInfo].py3_runtime.interpreter_version_info
    return [
        TestInfo(
            got = "{}.{}.{}".format(
                got_version.major,
                got_version.minor,
                got_version.micro,
            ),
            want = ctx.attr.want_version,
        ),
    ]

_simple_transition = rule(
    implementation = _lock_impl,
    attrs = {
        "python_version": attr.string(
            doc = "Public, see the docs in the macro.",
        ),
        "want_version": attr.string(
            doc = "Public, see the docs in the macro.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = [
        EXEC_TOOLS_TOOLCHAIN_TYPE,
    ],
    cfg = _python_version_transition,
)

def _test_toolchain_precedence(name):
    # First we expect the transitions with a specific version to always
    # give us that specific version
    exact_version_tests = {
        (v, v): v.replace(".", "_")
        for v in TOOL_VERSIONS
    }

    if BZLMOD_ENABLED:
        # Then we expect to get the version in the MINOR_MAPPING if we provide
        # the version from the MINOR_MAPPING
        minor_mapping_tests = {
            (minor, full): minor.replace(".", "_")
            for minor, full in MINOR_MAPPING.items()
        }

        # Lastly, if we don't provide any version to the transition, we should
        # get the default version
        default_version = full_version(
            version = DEFAULT_PYTHON_VERSION,
            minor_mapping = MINOR_MAPPING,
        )
        default_version_tests = {
            (None, default_version): "default",
        }
        tests = exact_version_tests | minor_mapping_tests | default_version_tests
    else:
        # Outside bzlmod the default version and the minor mapping tests do not
        # make sense because the user loading things in the WORKSPACE ultimately defines
        # the matching order.
        tests = exact_version_tests

    analysis_test(
        name = name,
        impl = _test_toolchain_precedence_impl,
        targets = {
            "{}_{}".format(name, test_name): rt_util.helper_target(
                _simple_transition,
                name = "{}_{}".format(name, test_name),
                python_version = input_version,
                want_version = want_version,
            )
            for (input_version, want_version), test_name in tests.items()
        },
    )

def _test_toolchain_precedence_impl(env, targets):
    # Check that the forwarded PyRuntimeInfo looks vaguely correct.
    for target in dir(targets):
        test_info = env.expect.that_target(target).provider(
            TestInfo,
            factory = lambda v, meta: v,
        )
        env.expect.that_str(test_info.got).equals(test_info.want)

_analysis_tests.append(_test_toolchain_precedence)

def define_toolchain_tests(name):
    """Define the toolchain tests.

    Args:
        name: Only present to satisfy tooling.
    """
    test_suite(
        name = name,
        tests = _analysis_tests,
    )

    for platform_key, platform_info in PLATFORMS.items():
        native.config_setting(
            name = "_is_{}".format(platform_key),
            flag_values = platform_info.flag_values,
            constraint_values = platform_info.compatible_with,
        )

    # First we expect the transitions with a specific version to always
    # give us that specific version
    exact_version_tests = {
        (v, v): "python_{}_test".format(v)
        for v in TOOL_VERSIONS
    }
    native.test_suite(
        name = "exact_version_tests",
        tests = exact_version_tests.values(),
    )

    if BZLMOD_ENABLED:
        # Then we expect to get the version in the MINOR_MAPPING if we provide
        # the version from the MINOR_MAPPING
        minor_mapping_tests = {
            (minor, full): "python_{}_test".format(minor)
            for minor, full in MINOR_MAPPING.items()
        }
        native.test_suite(
            name = "minor_mapping_tests",
            tests = minor_mapping_tests.values(),
        )

        # Lastly, if we don't provide any version to the transition, we should
        # get the default version
        default_version = full_version(
            version = DEFAULT_PYTHON_VERSION,
            minor_mapping = MINOR_MAPPING,
        )
        default_version_tests = {
            (None, default_version): "default_version_test",
        }
        tests = exact_version_tests | minor_mapping_tests | default_version_tests
    else:
        # Outside bzlmod the default version and the minor mapping tests do not
        # make sense because the user loading things in the WORKSPACE ultimately defines
        # the matching order.
        tests = exact_version_tests

    for (input_python_version, expect_python_version), test_name in tests.items():
        meta = TOOL_VERSIONS[expect_python_version]
        target_compatible_with = {
            "//conditions:default": ["@platforms//:incompatible"],
        }
        for platform_key in meta["sha256"].keys():
            is_platform = "_is_{}".format(platform_key)
            target_compatible_with[is_platform] = []

        py_reconfig_test(
            name = test_name,
            srcs = ["python_toolchain_test.py"],
            main = "python_toolchain_test.py",
            python_version = input_python_version,
            env = {
                "EXPECT_PYTHON_VERSION": expect_python_version,
            },
            deps = ["//python/runfiles"],
            data = ["//tests/support:current_build_settings"],
            target_compatible_with = select(target_compatible_with),
        )
