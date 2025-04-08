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

"""Implementation of the rules to expose a REPL."""

load("//python:py_binary.bzl", "py_binary")

def _generate_repl_main_impl(ctx):
    stub_repo = ctx.attr.stub.label.repo_name or ctx.workspace_name
    stub_path = "/".join([stub_repo, ctx.file.stub.short_path])

    ctx.actions.expand_template(
        template = ctx.file._template,
        output = ctx.outputs.out,
        substitutions = {
            "%stub_path%": stub_path,
        },
    )

_generate_repl_main = rule(
    implementation = _generate_repl_main_impl,
    attrs = {
        "out": attr.output(
            mandatory = True,
        ),
        "stub": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "_generator": attr.label(
            default = "//python/private:repl_main_generator",
            executable = True,
            cfg = "exec",
        ),
        "_template": attr.label(
            default = "//python/private:repl_template.py",
            allow_single_file = True,
        ),
    },
)

def py_repl_binary(name, stub, deps = [], data = [], **kwargs):
    _generate_repl_main(
        name = "%s_py" % name,
        stub = stub,
        out = "%s.py" % name,
    )

    py_binary(
        name = name,
        srcs = [
            ":%s.py" % name,
        ],
        data = data + [
            stub,
        ],
        deps = deps + [
            "//python/runfiles",
        ],
        **kwargs
    )
