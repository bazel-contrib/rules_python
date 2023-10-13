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

"""Generate the BUILD.bazel contents for a repo defined by a group_library."""

load(
    "//python/private:labels.bzl",
    "PY_LIBRARY_IMPL_LABEL",
    "PY_LIBRARY_PUBLIC_LABEL",
    "WHEEL_FILE_IMPL_LABEL",
    "WHEEL_FILE_PUBLIC_LABEL",
)
load("//python/private:normalize_name.bzl", "normalize_name")

_PRELUDE = """\
load("@rules_python//python:defs.bzl", "py_library", "py_binary")
"""

_GROUP_TEMPLATE = """\
## Group {name}

filegroup(
    name = "{name}_{whl_public_label}",
    srcs = [],
    data = {whl_deps},
    visibility = {visibility},
)

py_library(
    name = "{name}_{lib_public_label}",
    srcs = [],
    deps = {lib_deps},
    visibility = {visibility},
)
"""

def _generate_group_libraries(repo_prefix, group_name, group_members):
    """Generate the component libraries implementing a group.

    A group consists of two underlying composite libraries, one `filegroup`
    which wraps all the whls of the members and one `py_library` which wraps the
    pkgs of the members.

    Implementation detail of `generate_group_library_build_bazel` which uses
    this to construct a BUILD.bazel.

    Args:
        repo_prefix: str; the pip_parse repo prefix.
        group_name: str; the name which the user provided for the dep group.
        group_members: list[str]; the names of the _packages_ (not repositories)
          which make up the group.
    """

    lib_dependencies = [
        "@" + repo_prefix + normalize_name(d) + "//:" + PY_LIBRARY_IMPL_LABEL
        for d in group_members
    ]
    whl_file_deps = [
        "@" + repo_prefix + normalize_name(d) + "//:" + WHEEL_FILE_IMPL_LABEL
        for d in group_members
    ]
    visibility = [
        "@" + repo_prefix + normalize_name(d) + "//:__pkg__"
        for d in group_members
    ]

    return _GROUP_TEMPLATE.format(
        name = normalize_name(group_name),
        whl_public_label = WHEEL_FILE_PUBLIC_LABEL,
        whl_deps = repr(whl_file_deps),
        lib_public_label = PY_LIBRARY_PUBLIC_LABEL,
        lib_deps = repr(lib_dependencies),
        visibility = repr(visibility),
    )

def generate_group_library_build_bazel(
        repo_prefix,
        groups):
    """Generate a BUILD file for a repository of group implementations

    Args:
        repo_prefix: the repo prefix that should be used for dependency lists.
        groups: a mapping of group names to lists of names of component packages.

    Returns:
        A complete BUILD file as a string
    """

    content = [_PRELUDE]

    for group_name, group_members in groups.items():
        content.append(_generate_group_libraries(repo_prefix, group_name, group_members))

    return "\n\n".join(content)
