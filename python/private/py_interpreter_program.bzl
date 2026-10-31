# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Internal only bootstrap level binary-like rule."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//python/private:sentinel_impl.bzl", "SentinelInfo")

PyInterpreterProgramInfo = provider(
    doc = "Information about how to run a program with an external interpreter.",
    fields = {
        "env": "dict[str, str] of environment variables to set prior to execution.",
        "interpreter_args": "List of strings; additional args to pass " +
                            "to the interpreter before the main program.",
        "main": "File; the .py file that is the entry point.",
    },
)

def _stage_program_files(ctx):
    if not ctx.files.srcs:
        executable = ctx.actions.declare_file(
            "{}_.{}".format(ctx.label.name, ctx.file.main.extension),
        )
        ctx.actions.symlink(output = executable, target_file = ctx.file.main)
        return executable, [executable]

    # When additional `srcs` are present, stage `main` and all `srcs` as
    # siblings inside a private `<name>_/` directory so `Path(__file__).parent`
    # locates sibling modules under remote execution and on Windows without
    # symlinks, without resolving into the source tree.
    seen_basenames = {ctx.file.main.basename: ctx.file.main.short_path}
    executable = ctx.actions.declare_file(
        "{}_/{}".format(ctx.label.name, ctx.file.main.basename),
    )
    ctx.actions.symlink(output = executable, target_file = ctx.file.main)
    staged_srcs = []
    for src in ctx.files.srcs:
        if src.basename in seen_basenames:
            fail(
                "py_interpreter_program duplicate basename '{}' from '{}' and '{}'".format(
                    src.basename,
                    seen_basenames[src.basename],
                    src.short_path,
                ),
            )
        seen_basenames[src.basename] = src.short_path
        staged_src = ctx.actions.declare_file(
            "{}_/{}".format(ctx.label.name, src.basename),
        )
        ctx.actions.symlink(output = staged_src, target_file = src)
        staged_srcs.append(staged_src)

    return executable, [executable] + staged_srcs

def _py_interpreter_program_impl(ctx):
    # Bazel requires the executable file to be an output created by this target.
    executable, all_files = _stage_program_files(ctx)
    env = dict(ctx.attr.env)
    interpreter_args = list(ctx.attr.interpreter_args)
    if ctx.files.srcs:
        env = {"PYTHONDONTWRITEBYTECODE": "1"} | env
        if "-B" not in interpreter_args:
            interpreter_args = ["-B"] + interpreter_args

    execution_requirements = {}
    if BuildSettingInfo in ctx.attr.execution_requirements:
        execution_requirements.update([
            value.split("=", 1)
            for value in ctx.attr.execution_requirements[BuildSettingInfo].value
            if value.strip()
        ])

    return [
        DefaultInfo(
            executable = executable,
            files = depset(all_files),
            runfiles = ctx.runfiles(files = all_files),
        ),
        PyInterpreterProgramInfo(
            env = env,
            interpreter_args = interpreter_args,
            main = ctx.file.main,
        ),
        testing.ExecutionInfo(
            requirements = execution_requirements,
        ),
    ]

py_interpreter_program = rule(
    doc = """
Binary-like rule that doesn't require a toolchain because its part of
implementing build tools for the toolchain. This rule expects the Python
interprter to be externally provided.

To run a `py_interpreter_program` as an action, pass it as a tool that is
used by the actual interpreter executable. This ensures its runfiles are
setup. Also pass along any interpreter args, environment, and requirements.

```starlark
ctx.actions.run(
    executable = <python interpreter executable>,
    args = (
        target[PyInterpreterProgramInfo].interpreter_args +
        [target[DefaultInfo].files_to_run.executable]
    ),
    tools = target[DefaultInfo].files_to_run,
    env = target[PyInterpreterProgramInfo].env,
    execution_requirements = target[testing.ExecutionInfo].requirements,
)
```

""",
    implementation = _py_interpreter_program_impl,
    attrs = {
        "env": attr.string_dict(
            doc = "Environment variables that should set prior to running.",
        ),
        "execution_requirements": attr.label(
            default = "//python:none",
            doc = "Execution requirements to set when running it as an action",
            providers = [[BuildSettingInfo], [SentinelInfo]],
        ),
        "interpreter_args": attr.string_list(
            doc = "Args that should be passed to the interpreter.",
        ),
        "main": attr.label(
            doc = "The entry point Python file.",
            allow_single_file = True,
        ),
        "srcs": attr.label_list(
            doc = """
Additional Python source files imported by `main`.

When non-empty, `main` and `srcs` are staged flat as siblings inside a private
`<name>_/` directory (basenames must be unique), and `-B` plus
`PYTHONDONTWRITEBYTECODE=1` are enabled automatically so sibling imports do not
write `__pycache__` into the staging directory.
""",
            allow_files = [".py"],
        ),
    },
    # This is set to False because this isn't a binary/executable in the usual
    # Bazel sense (even though it sets DefaultInfo.files_to_run). It just holds
    # information so that a caller can construct how to execute it correctly.
    executable = False,
)
