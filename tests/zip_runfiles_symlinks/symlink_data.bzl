# Copyright 2026 The Bazel Authors. All rights reserved.
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
"""Test rule that exposes data via runfiles.symlinks / runfiles.root_symlinks."""

def _symlink_data_impl(ctx):
    return [DefaultInfo(
        runfiles = ctx.runfiles(
            symlinks = {
                "symlink_data/via_symlink.txt": ctx.file.symlinked,
            },
            root_symlinks = {
                "via_root_symlink.txt": ctx.file.root_symlinked,
            },
        ),
    )]

symlink_data = rule(
    implementation = _symlink_data_impl,
    attrs = {
        "root_symlinked": attr.label(allow_single_file = True, mandatory = True),
        "symlinked": attr.label(allow_single_file = True, mandatory = True),
    },
)
