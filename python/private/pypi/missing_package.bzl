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

"""Rule for generating an execution-phase action failure when a PyPI package is missing."""

load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:reexports.bzl", "BuiltinPyInfo")

def _missing_package_error_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".error")

    # Register an action that fails when Bazel attempts to stage/build this file
    ctx.actions.run_shell(
        outputs = [out],
        command = "echo 'Dependency Error: Third-party package \"{}\" is not available when building under PyPI hub \"{}\".' >&2 && exit 1".format(
            ctx.attr.package_name,
            ctx.attr.hub_name,
        ),
    )

    maybe_builtin = [BuiltinPyInfo(transitive_sources = depset([out]))] if BuiltinPyInfo != None else []

    return [
        DefaultInfo(
            files = depset([out]),
            data_runfiles = ctx.runfiles([out]),
        ),
        PyInfo(
            transitive_sources = depset([out]),
        ),
    ] + maybe_builtin

missing_package_error = rule(
    implementation = _missing_package_error_impl,
    attrs = {
        "hub_name": attr.string(mandatory = True),
        "package_name": attr.string(mandatory = True),
    },
)
