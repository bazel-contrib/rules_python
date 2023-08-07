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

"""
A private rule to generate an entry_point python file to be used in a py_binary.

Right now it only supports console_scripts via the entry_points.txt file in the dist-info.
"""

_ENTRY_POINTS_TXT = "entry_points.txt"
_TOOLCHAIN_TYPE = "//python:toolchain_type"

def _get_entry_points_txt(dist_info):
    for file in dist_info.files.to_list():
        if file.basename == _ENTRY_POINTS_TXT:
            return file

    fail("{} does not contain {}".format(dist_info, _ENTRY_POINTS_TXT))

def _impl(ctx):
    runtime = ctx.toolchains["//python:toolchain_type"].py3_runtime
    python = runtime.interpreter or runtime.interpreter_path

    entry_points_txt = _get_entry_points_txt(ctx.attr.dist_info)

    args = ctx.actions.args()
    args.add(ctx.file._tool)
    args.add("--script", ctx.attr.script)
    args.add(entry_points_txt)
    args.add(ctx.outputs.out)

    ctx.actions.run(
        inputs = [
            ctx.file._tool,
            entry_points_txt,
        ],
        outputs = [ctx.outputs.out],
        arguments = [args],
        executable = python,
        toolchain = _TOOLCHAIN_TYPE,
    )

    return [DefaultInfo(
        files = depset([ctx.outputs.out]),
    )]

py_entry_point_gen = rule(
    _impl,
    attrs = {
        "dist_info": attr.label(
            doc = "The dist-info files for the package.",
            mandatory = True,
        ),
        "out": attr.output(
            doc = "Output file location.",
            mandatory = True,
        ),
        "script": attr.string(
            doc = "The name of the script to create the entry_point file for.",
            default = "",
        ),
        "_tool": attr.label(
            default = "//python/pip_install/tools/entry_point_generator:generator.py",
            allow_single_file = [".py"],
        ),
    },
    toolchains = [_TOOLCHAIN_TYPE],
    doc = """\
Builds an entry_point script from an entry_points.txt file.

NOTE @aignas 2023-08-07: This cannot be in pure starlark, because we need to
read a file and then create a `.py` file based on the contents of that file,
which cannot be done in pure starlark according to
https://github.com/bazelbuild/bazel/issues/14744
""",
)
