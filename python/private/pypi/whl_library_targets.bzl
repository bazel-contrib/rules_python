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

"""Macro to generate all of the targets present in a {obj}`whl_library`."""

load(":whl_library_deps_targets.bzl", "whl_library_deps_targets")
load(":whl_library_srcs.bzl", "whl_library_srcs")

def whl_library_targets(
        *,
        name,
        metadata_name = "",
        requires_dist = [],
        extras = [],
        entry_points = {},
        include = [],
        group_deps = [],
        group_name = None,
        dep_template = None,
        data_exclude = [],
        enable_implicit_namespace_pkgs = False,
        sdist_filename = None,
        namespace_package_files = [],
        filegroups = None,
        copy_files = {},
        copy_executables = {},
        srcs_exclude = [],
        data = [],
        visibility = ["//visibility:public"],
        **kwargs):
    """The macro to create whl targets from the METADATA.

    Args:
        name: {type}`str` The wheel filename
        metadata_name: {type}`str` The package name as written in wheel `METADATA`.
        group_deps: {type}`list[str]` names of fellow members of the group (if
            any). These will be excluded from generated deps lists so as to avoid
            direct cycles. These dependencies will be provided at runtime by the
            group rules which wrap this library and its fellows together.
        requires_dist: {type}`list[str]` The list of `Requires-Dist` values from
            the whl `METADATA`.
        extras: {type}`list[str]` The list of requested extras. This essentially includes extra transitive dependencies in the final targets depending on the wheel `METADATA`.
        entry_points: {type}`list[dict]` A list of parsed entry point definitions.
        include: {type}`list[str]` The list of packages to include.
        group_name: {type}`str | None` name of the dependency group (if any).
        dep_template: {type}`str | None` The dep_template to use.
        data_exclude: {type}`list[str]` The globs for data attribute exclusion.
        enable_implicit_namespace_pkgs: {type}`boolean` generate __init__.py files for namespace pkgs.
        sdist_filename: {type}`str | None` The filename of the sdist.
        namespace_package_files: {type}`list[str]` A list of labels of files whose directories are namespace packages.
        filegroups: {type}`dict[str, list[str]] | None` A dictionary of the target names and the glob matches.
        copy_files: {type}`dict[str, str]` The mapping between src and dest locations.
        copy_executables: {type}`dict[str, str]` The mapping between src and dest locations for executables.
        srcs_exclude: {type}`list[str]` The globs for srcs attribute exclusion.
        data: {type}`list[str]` A list of labels to include as part of the `data` attribute.
        visibility: {type}`list[str]` The visibility of the targets.
        **kwargs: Extra args passed to the {obj}`whl_library_deps_targets` and {obj}`whl_library_srcs`.
    """
    whl_library_srcs(
        name = name,
        sdist_filename = sdist_filename,
        data_exclude = data_exclude,
        srcs_exclude = srcs_exclude,
        filegroups = filegroups,
        entry_points = entry_points,
        visibility = visibility,
        data = data,
        copy_files = copy_files,
        copy_executables = copy_executables,
        enable_implicit_namespace_pkgs = enable_implicit_namespace_pkgs,
        namespace_package_files = namespace_package_files,
        **kwargs
    )

    whl_library_deps_targets(
        name = name,
        metadata_name = metadata_name,
        requires_dist = requires_dist,
        dep_template = dep_template,  # only needed if requires_dist or group_name is present
        group_deps = group_deps,  # only needed if group_name is present
        group_name = group_name,  # must specify group_deps together
        extras = extras,  # only needed if requires_dist is present
        include = include,  # only needed if requires_dist is present
        repo = None,  # set aliases in the same repo
        aliases = {},
        **kwargs
    )
