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
"""Starlark tests for py_exec_tools_toolchain rule."""

load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load(
    "//python/private:py_exec_tools_toolchain.bzl",
    "current_interpreter_executable",
    "py_exec_tools_toolchain",
)  # buildifier: disable=bzl-visibility
load(
    "//python/private:toolchain_types.bzl",
    "EXEC_TOOLS_TOOLCHAIN_TYPE",
)  # buildifier: disable=bzl-visibility

_tests = []

def _test_disable_exec_interpreter(name):
    py_exec_tools_toolchain(
        name = name + "_subject",
        exec_interpreter = "//python/private:sentinel",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_disable_exec_interpreter_impl,
    )

def _test_disable_exec_interpreter_impl(env, target):
    exec_tools = target[platform_common.ToolchainInfo].exec_tools
    env.expect.that_bool(exec_tools.exec_interpreter == None).equals(True)

_tests.append(_test_disable_exec_interpreter)

def _test_default_exec_interpreter(name):
    py_exec_tools_toolchain(
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_default_exec_interpreter_impl,
    )

def _test_default_exec_interpreter_impl(env, target):
    exec_tools = target[platform_common.ToolchainInfo].exec_tools
    env.expect.that_bool(exec_tools.exec_interpreter != None).equals(True)
    target_info = exec_tools.exec_interpreter
    env.expect.that_bool(DefaultInfo in target_info).equals(True)
    env.expect.that_bool(
        target_info[DefaultInfo].files_to_run != None,
    ).equals(True)
    env.expect.that_bool(
        target_info[DefaultInfo].files_to_run.executable != None,
    ).equals(True)

_tests.append(_test_default_exec_interpreter)

def _test_current_interpreter_executable(name):
    current_interpreter_executable(
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_current_interpreter_executable_impl,
    )

def _test_current_interpreter_executable_impl(env, target):
    env.expect.that_bool(DefaultInfo in target).equals(True)
    env.expect.that_bool(platform_common.ToolchainInfo in target).equals(True)
    env.expect.that_bool(
        target[DefaultInfo].files_to_run != None,
    ).equals(True)
    env.expect.that_bool(
        target[DefaultInfo].files_to_run.executable != None,
    ).equals(True)

_tests.append(_test_current_interpreter_executable)

def py_exec_tools_toolchain_test_suite(name):
    test_suite(name = name, tests = _tests)

def _run_interpreter_action_impl(ctx):
    exec_tools = ctx.toolchains[EXEC_TOOLS_TOOLCHAIN_TYPE].exec_tools
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    ctx.actions.run(
        executable = exec_tools.exec_interpreter[DefaultInfo].files_to_run,
        arguments = [
            ctx.file.src.path,
            out.path,
        ],
        inputs = [ctx.file.src],
        outputs = [out],
        mnemonic = "TestRunInterpreterAction",
        progress_message = "Running interpreter action: %{label}",
    )
    return [DefaultInfo(files = depset([out]))]

_run_interpreter_action = rule(
    implementation = _run_interpreter_action_impl,
    attrs = {
        "src": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Python script to execute with the interpreter.",
        ),
    },
    toolchains = [EXEC_TOOLS_TOOLCHAIN_TYPE],
    doc = """Runs Python script using exec_tools.exec_interpreter.""",
)

def interpreter_run_in_action_test(
        name,
        src = "test_action.py",
        expected = "expected_action_output.json",
        **kwargs):
    """Runs a Python script using the exec interpreter and diffs the output.

    Args:
        name: The name of the diff_test target.
        src: The Python script to execute.
        expected: The expected golden output file to compare against.
        **kwargs: Additional keyword arguments forwarded to diff_test.
    """
    actual_target = name + "_actual"
    _run_interpreter_action(
        name = actual_target,
        src = src,
        tags = ["manual"],
    )
    diff_test(
        name = name,
        file1 = ":" + actual_target,
        file2 = expected,
        **kwargs
    )
