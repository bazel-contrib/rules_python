# Copyright 2023 The Bazel Authors. All rights reserved.
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
"""Starlark tests for PyRuntimeInfo provider."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("//python:py_runtime_info.bzl", "PyRuntimeInfo")
load("//tests/support:py_runtime_info_subject.bzl", "py_runtime_info_subject")

def _create_py_runtime_info_without_interpreter_version_info_impl(ctx):
    return [PyRuntimeInfo(
        interpreter = ctx.file.interpreter,
        files = depset(ctx.files.files),
        python_version = "PY3",
        bootstrap_template = ctx.attr.bootstrap_template,
    )]

_create_py_runtime_info_without_interpreter_version_info = rule(
    implementation = _create_py_runtime_info_without_interpreter_version_info_impl,
    attrs = {
        "bootstrap_template": attr.label(allow_single_file = True, default = "bootstrap.txt"),
        "files": attr.label_list(allow_files = True, default = ["data.txt"]),
        "interpreter": attr.label(allow_single_file = True, default = "interpreter.sh"),
        "python_version": attr.string(default = "PY3"),
    },
)

def _simple_binary_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(executable, "", is_executable = True)
    return [DefaultInfo(
        executable = executable,
        files = depset([executable]),
    )]

_simple_binary = rule(
    implementation = _simple_binary_impl,
    executable = True,
)

def _file_target_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(output, "")
    return [DefaultInfo(files = depset([output]))]

_file_target = rule(
    implementation = _file_target_impl,
)

def _create_py_runtime_info_with_interpreter_files_to_run_impl(ctx):
    files_to_run = ctx.attr.files_to_run[DefaultInfo].files_to_run
    kwargs = dict(
        bootstrap_template = ctx.file.bootstrap_template,
        interpreter_files_to_run = files_to_run,
        python_version = "PY3",
    )
    if ctx.attr.use_interpreter_path:
        kwargs["interpreter_path"] = "/python"
    else:
        kwargs["files"] = depset()
        kwargs["interpreter"] = ctx.executable.interpreter

    return [PyRuntimeInfo(**kwargs)]

_create_py_runtime_info_with_interpreter_files_to_run = rule(
    implementation = _create_py_runtime_info_with_interpreter_files_to_run_impl,
    attrs = {
        "bootstrap_template": attr.label(allow_single_file = True, default = "bootstrap.txt"),
        "files_to_run": attr.label(mandatory = True),
        "interpreter": attr.label(
            cfg = "target",
            executable = True,
            mandatory = True,
        ),
        "use_interpreter_path": attr.bool(),
    },
)

_tests = []

def _test_can_create_py_runtime_info_without_interpreter_version_info(name):
    _create_py_runtime_info_without_interpreter_version_info(
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_can_create_py_runtime_info_without_interpreter_version_info_impl,
    )

def _test_can_create_py_runtime_info_without_interpreter_version_info_impl(env, target):
    # If we get this for, construction succeeded, so nothing to check
    _ = env, target  # @unused

_tests.append(_test_can_create_py_runtime_info_without_interpreter_version_info)

def _test_interpreter_files_to_run_with_interpreter(name):
    _simple_binary(
        name = name + "_interpreter",
    )
    _create_py_runtime_info_with_interpreter_files_to_run(
        name = name + "_subject",
        files_to_run = name + "_interpreter",
        interpreter = name + "_interpreter",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_interpreter_files_to_run_with_interpreter_impl,
    )

def _test_interpreter_files_to_run_with_interpreter_impl(env, target):
    info = env.expect.that_target(target).provider(
        PyRuntimeInfo,
        factory = py_runtime_info_subject,
    )
    info.interpreter().short_path_equals("{package}/{test_name}_interpreter")
    info.interpreter_files_to_run().executable().short_path_equals(
        "{package}/{test_name}_interpreter",
    )

_tests.append(_test_interpreter_files_to_run_with_interpreter)

def _test_interpreter_files_to_run_disallows_interpreter_path(name):
    _simple_binary(
        name = name + "_interpreter",
    )
    _create_py_runtime_info_with_interpreter_files_to_run(
        name = name + "_subject",
        files_to_run = name + "_interpreter",
        interpreter = name + "_interpreter",
        tags = ["manual"],
        use_interpreter_path = True,
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_interpreter_files_to_run_disallows_interpreter_path_impl,
        expect_failure = True,
    )

def _test_interpreter_files_to_run_disallows_interpreter_path_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*interpreter_files_to_run*interpreter_path*"),
    )

_tests.append(_test_interpreter_files_to_run_disallows_interpreter_path)

def _test_interpreter_files_to_run_requires_executable(name):
    _simple_binary(
        name = name + "_interpreter",
    )
    _file_target(
        name = name + "_files_to_run",
    )
    _create_py_runtime_info_with_interpreter_files_to_run(
        name = name + "_subject",
        files_to_run = name + "_files_to_run",
        interpreter = name + "_interpreter",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_interpreter_files_to_run_requires_executable_impl,
        expect_failure = True,
    )

def _test_interpreter_files_to_run_requires_executable_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*interpreter_files_to_run*executable*"),
    )

_tests.append(_test_interpreter_files_to_run_requires_executable)

def _test_interpreter_files_to_run_requires_matching_interpreter(name):
    _simple_binary(
        name = name + "_interpreter",
    )
    _simple_binary(
        name = name + "_other_interpreter",
    )
    _create_py_runtime_info_with_interpreter_files_to_run(
        name = name + "_subject",
        files_to_run = name + "_other_interpreter",
        interpreter = name + "_interpreter",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_interpreter_files_to_run_requires_matching_interpreter_impl,
        expect_failure = True,
    )

def _test_interpreter_files_to_run_requires_matching_interpreter_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*interpreter_files_to_run.executable*interpreter*"),
    )

_tests.append(_test_interpreter_files_to_run_requires_matching_interpreter)

def py_runtime_info_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
