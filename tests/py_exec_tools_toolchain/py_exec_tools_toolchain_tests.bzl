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
    files_to_run = exec_tools.exec_interpreter[DefaultInfo].files_to_run
    env.expect.that_bool(files_to_run != None).equals(True)
    env.expect.that_bool(files_to_run.executable != None).equals(True)

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
    default_info = target[DefaultInfo]
    env.expect.that_bool(default_info.files_to_run != None).equals(True)
    env.expect.that_bool(
        default_info.files_to_run.executable != None,
    ).equals(True)
    env.expect.that_bool(default_info.default_runfiles != None).equals(True)

_tests.append(_test_current_interpreter_executable)

def py_exec_tools_toolchain_test_suite(name):
    test_suite(name = name, tests = _tests)

def _run_interpreter_action_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".json")
    exec_tools = ctx.toolchains[EXEC_TOOLS_TOOLCHAIN_TYPE].exec_tools
    if not exec_tools.exec_interpreter:
        fail("exec_tools.exec_interpreter is not configured")
    executable = exec_tools.exec_interpreter[DefaultInfo].files_to_run
    ctx.actions.run(
        outputs = [out],
        inputs = [ctx.file.src],
        executable = executable,
        arguments = [ctx.file.src.path, out.path],
        mnemonic = "RunInterpreterAction",
        progress_message = "Running interpreter action %{label}",
        toolchain = EXEC_TOOLS_TOOLCHAIN_TYPE,
    )
    return [DefaultInfo(files = depset([out]))]

_run_interpreter_action = rule(
    implementation = _run_interpreter_action_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
    },
    toolchains = [EXEC_TOOLS_TOOLCHAIN_TYPE],
)

def interpreter_run_in_action_test(
        name,
        src = None,
        expected = None,
        **kwargs):
    """Runs a Python script in a build action using the exec interpreter.

    Args:
        name: Name of the test target.
        src: The Python source file to execute.
        expected: The expected output file to compare against.
        **kwargs: Passed to diff_test.
    """
    src = src or str(Label("//tests/py_exec_tools_toolchain:test_action.py"))
    expected = expected or str(
        Label("//tests/py_exec_tools_toolchain:expected_action_output.json"),
    )
    action_target = name + "_action"
    _run_interpreter_action(
        name = action_target,
        src = src,
        tags = ["manual"],
    )
    diff_test(
        name = name,
        file1 = ":" + action_target,
        file2 = expected,
        **kwargs
    )
