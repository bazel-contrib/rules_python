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

load("//python/private:normalize_name.bzl", "normalize_name")
load(":labels.bzl", "PY_LIBRARY_PUBLIC_LABEL")
load(":pep508_deps.bzl", _pep508_deps = "deps")
load(":py_sdist_wheel.bzl", "BOOTSTRAP_BUILD_PACKAGES")
load(
    ":whl_library_deps_targets.bzl",
    "config_settings",
    "select_deps",
    _whl_library_deps_targets = "whl_library_deps_targets",
)
load(":whl_library_srcs.bzl", _whl_library_srcs = "whl_library_srcs")

whl_library_deps_targets = _whl_library_deps_targets
whl_library_srcs = _whl_library_srcs

def _resolve_sdist_build_deps(
        *,
        name,
        sdist,
        metadata_name,
        dep_template,
        group_deps,
        include,
        kwargs):
    sdist = dict(sdist)
    build_requires = sdist.pop("build_requires", [])
    build_deps = list(sdist.get("build_deps", []))
    if not (build_requires and dep_template):
        if build_deps:
            sdist["build_deps"] = build_deps
        return sdist

    user_dep_names = []
    for d in build_deps:
        _, _, pkg_and_target = d.partition("//")
        pkg_part, _, target_part = pkg_and_target.partition(":")
        if pkg_part:
            user_dep_names.append(normalize_name(pkg_part.rpartition("/")[2]))
        if target_part:
            user_dep_names.append(normalize_name(target_part))
    excludes = group_deps + BOOTSTRAP_BUILD_PACKAGES.keys() + user_dep_names

    if include and not build_deps:
        all_build_reqs = _pep508_deps(
            name = metadata_name,
            requires_dist = build_requires,
            excludes = excludes,
        )
        include_set = {normalize_name(n): True for n in include}
        missing = [r for r in all_build_reqs.deps if r not in include_set]
        if missing:
            fail(
                "In '{}', sdist build requires {} which are not present in the pip hub ".format(
                    name,
                    ", ".join(missing),
                ) +
                "packages or bootstrap dependencies ({}). Add them to your requirements ".format(
                    ", ".join(sorted(BOOTSTRAP_BUILD_PACKAGES.keys())),
                ) +
                "lockfile or specify 'sdist_build_deps' via pip.whl_mods / package_annotation.",
            )

    build_pkg_deps = _pep508_deps(
        name = metadata_name,
        requires_dist = build_requires,
        excludes = excludes,
        include = include,
    )
    config_settings(
        dependencies_with_markers = build_pkg_deps.deps_select,
        setting_prefix = "include_sdist_build_",
        **({"rules": kwargs["rules"]} if "rules" in kwargs else {})
    )
    build_deps = select_deps(
        deps = build_deps,
        package_deps = build_pkg_deps,
        tmpl = dep_template.format(name = "{}", target = PY_LIBRARY_PUBLIC_LABEL),
        setting_prefix = "include_sdist_build_",
    )
    if build_deps:
        sdist["build_deps"] = build_deps
    return sdist

def whl_library_targets(
        *,
        name,
        whl_file = None,
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
        action_install = False,
        extracted_files = [],
        has_entry_points_txt = False,
        shebang_scripts = [],
        sdist = None,
        visibility = ["//visibility:public"],
        **kwargs):
    """The macro to create whl targets from the METADATA.

    Args:
        name: {type}`str` The wheel filename
        whl_file: {type}`str | None` The label of a wheel stored in another repository.
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
        action_install: {type}`bool` Whether to install the wheel in a build action.
        extracted_files: {type}`list[str]` Relative paths under the installed wheel directory.
        has_entry_points_txt: {type}`bool` Whether a fetch-time `entry_points.txt` file exists in the package.
        shebang_scripts: {type}`list[str]` Top-level script names in `.data/scripts/` with `#!python` shebangs.
        sdist: {type}`dict | None` Keyword arguments for `py_sdist_wheel` (plus `build_requires` and `site_paths`) when building an sdist in an action.
        visibility: {type}`list[str]` The visibility of the targets.
        **kwargs: Extra args passed to the {obj}`whl_library_deps_targets` and {obj}`whl_library_srcs`.
    """
    if sdist != None:
        sdist = _resolve_sdist_build_deps(
            name = name,
            sdist = sdist,
            metadata_name = metadata_name,
            dep_template = dep_template,
            group_deps = group_deps,
            include = include,
            kwargs = kwargs,
        )

    whl_library_srcs(
        name = name,
        whl_file = whl_file,
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
        action_install = action_install,
        extracted_files = extracted_files,
        has_entry_points_txt = has_entry_points_txt,
        shebang_scripts = shebang_scripts,
        sdist = sdist,
        **kwargs
    )

    if dep_template:
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
