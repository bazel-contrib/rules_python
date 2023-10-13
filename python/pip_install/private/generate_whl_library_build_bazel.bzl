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

"""Generate the BUILD.bazel contents for a repo defined by a whl_library."""

load(
    "//python/private:labels.bzl",
    "DATA_LABEL",
    "DIST_INFO_LABEL",
    "PY_LIBRARY_IMPL_LABEL",
    "PY_LIBRARY_PUBLIC_LABEL",
    "WHEEL_ENTRY_POINT_PREFIX",
    "WHEEL_FILE_IMPL_LABEL",
    "WHEEL_FILE_PUBLIC_LABEL",
)
load("//python/private:normalize_name.bzl", "normalize_name")

_COPY_FILE_TEMPLATE = """\
copy_file(
    name = "{dest}.copy",
    src = "{src}",
    out = "{dest}",
    is_executable = {is_executable},
)
"""

_ENTRY_POINT_RULE_TEMPLATE = """\
py_binary(
    name = "{name}",
    srcs = ["{src}"],
    # This makes this directory a top-level in the python import
    # search path for anything that depends on this.
    imports = ["."],
    deps = ["{pkg}"],
)
"""

_BUILD_TEMPLATE = """\
load("@rules_python//python:defs.bzl", "py_library", "py_binary")
load("@bazel_skylib//rules:copy_file.bzl", "copy_file")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "{dist_info_label}",
    srcs = glob(["site-packages/*.dist-info/**"], allow_empty = True),
)

filegroup(
    name = "{data_label}",
    srcs = glob(["data/**"], allow_empty = True),
)

filegroup(
    name = "{whl_file_impl_label}",
    srcs = ["{whl_name}"],
    data = {whl_file_deps},
)

py_library(
    name = "{py_library_impl_label}",
    srcs = glob(
        ["site-packages/**/*.py"],
        exclude={srcs_exclude},
        # Empty sources are allowed to support wheels that don't have any
        # pure-Python code, e.g. pymssql, which is written in Cython.
        allow_empty = True,
    ),
    data = {data} + glob(
        ["site-packages/**/*"],
        exclude={data_exclude},
    ),
    # This makes this directory a top-level in the python import
    # search path for anything that depends on this.
    imports = ["site-packages"],
    deps = {dependencies},
    tags = {tags},
)

alias(
   name = "{py_library_public_label}",
   actual = "{py_library_actual_label}",
)

alias(
   name = "{whl_file_public_label}",
   actual = "{whl_file_actual_label}",
)
"""

def generate_whl_library_build_bazel(
        *,
        repo_prefix,
        whl_name,
        dependencies,
        data_exclude,
        tags,
        entry_points,
        annotation = None,
        group_name = None,
        group_deps = []):
    """Generate a BUILD file for an unzipped Wheel

    Args:
        repo_prefix: the repo prefix that should be used for dependency lists.
        whl_name: the whl_name that this is generated for.
        dependencies: a list of PyPI packages that are dependencies to the py_library.
        data_exclude: more patterns to exclude from the data attribute of generated py_library rules.
        tags: list of tags to apply to generated py_library rules.
        entry_points: A dict of entry points to add py_binary rules for.
        annotation: The annotation for the build file.
        group_name: Optional[str]; name of the dependency group (if any) which contains this library.
          If set, this library will behave as a shim to group implementation rules which will provide
          simultaneously installed dependencies which would otherwise form a cycle.
        group_deps: List[str]; names of fellow members of the group (if any). These will be excluded
          from generated deps lists so as to avoid direct cycles. These dependencies will be provided
          at runtime by the group rules which wrap this library and its fellows together.

    Returns:
        A complete BUILD file as a string
    """

    additional_content = []
    data = []
    srcs_exclude = []
    data_exclude = [] + data_exclude
    dependencies = sorted([normalize_name(d) for d in dependencies])
    tags = sorted(tags)

    for entry_point, entry_point_script_name in entry_points.items():
        additional_content.append(
            _generate_entry_point_rule(
                name = "{}_{}".format(WHEEL_ENTRY_POINT_PREFIX, entry_point),
                script = entry_point_script_name,
                pkg = ":" + PY_LIBRARY_PUBLIC_LABEL,
            ),
        )

    if annotation:
        for src, dest in annotation.copy_files.items():
            data.append(dest)
            additional_content.append(_generate_copy_commands(src, dest))
        for src, dest in annotation.copy_executables.items():
            data.append(dest)
            additional_content.append(
                _generate_copy_commands(src, dest, is_executable = True),
            )
        data.extend(annotation.data)
        data_exclude.extend(annotation.data_exclude_glob)
        srcs_exclude.extend(annotation.srcs_exclude_glob)
        if annotation.additive_build_content:
            additional_content.append(annotation.additive_build_content)

    _data_exclude = [
        "**/* *",
        "**/*.py",
        "**/*.pyc",
        "**/*.pyc.*",  # During pyc creation, temp files named *.pyc.NNNN are created
        # RECORD is known to contain sha256 checksums of files which might include the checksums
        # of generated files produced when wheels are installed. The file is ignored to avoid
        # Bazel caching issues.
        "**/*.dist-info/RECORD",
    ]
    for item in data_exclude:
        if item not in _data_exclude:
            _data_exclude.append(item)

    # Ensure this list is normalized
    # Note: mapping used as set
    group_deps = {
        normalize_name(d): True
        for d in group_deps
    }

    non_group_deps = [
        d
        for d in dependencies
        if d not in group_deps
    ]

    lib_dependencies = [
        "@" + repo_prefix + normalize_name(d) + "//:" + PY_LIBRARY_PUBLIC_LABEL
        for d in non_group_deps
    ]
    whl_file_deps = [
        "@" + repo_prefix + normalize_name(d) + "//:" + WHEEL_FILE_PUBLIC_LABEL
        for d in non_group_deps
    ]

    contents = "\n".join(
        [
            _BUILD_TEMPLATE.format(
                py_library_public_label = PY_LIBRARY_PUBLIC_LABEL,
                py_library_impl_label = PY_LIBRARY_IMPL_LABEL,
                py_library_actual_label = ("@" + repo_prefix + "_groups//:" + normalize_name(group_name) + "_" + PY_LIBRARY_PUBLIC_LABEL) if group_name else PY_LIBRARY_IMPL_LABEL,
                dependencies = repr(lib_dependencies),
                data_exclude = repr(_data_exclude),
                whl_name = whl_name,
                whl_file_public_label = WHEEL_FILE_PUBLIC_LABEL,
                whl_file_impl_label = WHEEL_FILE_IMPL_LABEL,
                whl_file_actual_label = ("@" + repo_prefix + "_groups//:" + normalize_name(group_name) + "_" + WHEEL_FILE_PUBLIC_LABEL) if group_name else WHEEL_FILE_IMPL_LABEL,
                whl_file_deps = repr(whl_file_deps),
                tags = repr(tags),
                data_label = DATA_LABEL,
                dist_info_label = DIST_INFO_LABEL,
                entry_point_prefix = WHEEL_ENTRY_POINT_PREFIX,
                srcs_exclude = repr(srcs_exclude),
                data = repr(data),
            ),
        ] + additional_content,
    )

    # NOTE: Ensure that we terminate with a new line
    return contents.rstrip() + "\n"

def _generate_copy_commands(src, dest, is_executable = False):
    """Generate a [@bazel_skylib//rules:copy_file.bzl%copy_file][cf] target

    [cf]: https://github.com/bazelbuild/bazel-skylib/blob/1.1.1/docs/copy_file_doc.md

    Args:
        src (str): The label for the `src` attribute of [copy_file][cf]
        dest (str): The label for the `out` attribute of [copy_file][cf]
        is_executable (bool, optional): Whether or not the file being copied is executable.
            sets `is_executable` for [copy_file][cf]

    Returns:
        str: A `copy_file` instantiation.
    """
    return _COPY_FILE_TEMPLATE.format(
        src = src,
        dest = dest,
        is_executable = is_executable,
    )

def _generate_entry_point_rule(*, name, script, pkg):
    """Generate a Bazel `py_binary` rule for an entry point script.

    Note that the script is used to determine the name of the target. The name of
    entry point targets should be uniuqe to avoid conflicts with existing sources or
    directories within a wheel.

    Args:
        name (str): The name of the generated py_binary.
        script (str): The path to the entry point's python file.
        pkg (str): The package owning the entry point. This is expected to
            match up with the `py_library` defined for each repository.

    Returns:
        str: A `py_binary` instantiation.
    """
    return _ENTRY_POINT_RULE_TEMPLATE.format(
        name = name,
        src = script.replace("\\", "/"),
        pkg = pkg,
    )
