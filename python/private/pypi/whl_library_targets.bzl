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

load("@bazel_skylib//rules:copy_file.bzl", "copy_file")
load("//python:py_binary.bzl", "py_binary")
load("//python:py_library.bzl", "py_library")
load("//python/private:normalize_name.bzl", "normalize_name")
load(":env_marker_setting.bzl", "env_marker_setting")
load(
    ":labels.bzl",
    "DATA_LABEL",
    "DIST_INFO_LABEL",
    "EXTRACTED_WHEEL_FILES",
    "PY_LIBRARY_IMPL_LABEL",
    "PY_LIBRARY_PUBLIC_LABEL",
    "WHEEL_FILE_IMPL_LABEL",
    "WHEEL_FILE_PUBLIC_LABEL",
)
load(":namespace_pkgs.bzl", _create_inits = "create_inits")
load(":pep508_deps.bzl", "deps")
load(":venv_entry_point.bzl", "venv_entry_point")
load(":venv_rewrite_shebang.bzl", "venv_rewrite_shebang")

# Files that are special to the Bazel processing of things.
_BAZEL_REPO_FILE_GLOBS = [
    "BUILD",
    "BUILD.bazel",
    "REPO.bazel",
    "WORKSPACE",
    "WORKSPACE.bzlmod",
    "WORKSPACE.bazel",
]

_IS_VENV_SITE_PACKAGES_YES = Label("//python/config_settings:_is_venvs_site_packages_yes")
_VENV_SITE_PACKAGES_FLAG = Label("//python/config_settings:venvs_site_packages")

def whl_library_targets_from_requires(
        *,
        name,
        metadata_name = "",
        metadata_version = "",
        requires_dist = [],
        extras = [],
        entry_points = {},
        include = [],
        group_deps = [],
        **kwargs):
    """The macro to create whl targets from the METADATA.

    Args:
        name: {type}`str` The wheel filename
        metadata_name: {type}`str` The package name as written in wheel `METADATA`.
        metadata_version: {type}`str` The package version as written in wheel `METADATA`.
        group_deps: {type}`list[str]` names of fellow members of the group (if
            any). These will be excluded from generated deps lists so as to avoid
            direct cycles. These dependencies will be provided at runtime by the
            group rules which wrap this library and its fellows together.
        requires_dist: {type}`list[str]` The list of `Requires-Dist` values from
            the whl `METADATA`.
        extras: {type}`list[str]` The list of requested extras. This essentially includes extra transitive dependencies in the final targets depending on the wheel `METADATA`.
        entry_points: {type}`list[dict]` A list of parsed entry point definitions.
        include: {type}`list[str]` The list of packages to include.
        **kwargs: Extra args passed to the {obj}`whl_library_targets`
    """
    package_deps = _parse_requires_dist(
        name = metadata_name,
        requires_dist = requires_dist,
        excludes = group_deps,
        extras = extras,
        include = include,
    )

    whl_library_targets(
        name = name,
        dependencies = package_deps.deps,
        dependencies_with_markers = package_deps.deps_select,
        entry_points = entry_points,
        tags = [
            "pypi_name={}".format(metadata_name),
            "pypi_version={}".format(metadata_version),
        ],
        **kwargs
    )

def _parse_requires_dist(
        *,
        name,
        requires_dist,
        excludes,
        include,
        extras):
    return deps(
        name = normalize_name(name),
        requires_dist = requires_dist,
        excludes = excludes,
        include = include,
        extras = extras,
    )

def whl_library_targets(
        *,
        name,
        dep_template,
        sdist_filename = None,
        data_exclude = [],
        srcs_exclude = [],
        tags = [],
        dependencies = [],
        filegroups = None,
        dependencies_with_markers = {},
        entry_points = {},
        group_name = "",
        data = [],
        copy_files = {},
        copy_executables = {},
        native = native,
        enable_implicit_namespace_pkgs = False,
        namespace_package_files = [],
        rules = struct(
            copy_file = copy_file,
            py_binary = py_binary,
            py_library = py_library,
            venv_entry_point = venv_entry_point,
            venv_rewrite_shebang = venv_rewrite_shebang,
            env_marker_setting = env_marker_setting,
            create_inits = _create_inits,
        )):
    """Create all of the whl_library targets.

    Args:
        name: {type}`str` The file to match for including it into the `whl`
            filegroup. This may be also parsed to generate extra metadata.
        dep_template: {type}`str` The dep_template to use for dependency
            interpolation.
        sdist_filename: {type}`str | None` If the wheel was built from an sdist,
            the filename of the sdist.
        tags: {type}`list[str]` The tags set on the `py_library`.
        dependencies: {type}`list[str]` A list of dependencies.
        dependencies_with_markers: {type}`dict[str, str]` A marker to evaluate
            in order for the dep to be included.
        entry_points: {type}`list[dict]` A list of parsed entry point definitions.
        filegroups: {type}`dict[str, list[str]] | None` A dictionary of the target
            names and the glob matches. If `None`, defaults will be used.
        group_name: {type}`str` name of the dependency group (if any) which
            contains this library. If set, this library will behave as a shim
            to group implementation rules which will provide simultaneously
            installed dependencies which would otherwise form a cycle.
        copy_executables: {type}`dict[str, str]` The mapping between src and
            dest locations for the targets.
        copy_files: {type}`dict[str, str]` The mapping between src and
            dest locations for the targets.
        data_exclude: {type}`list[str]` The globs for data attribute exclusion
            in `py_library`.
        srcs_exclude: {type}`list[str]` The globs for srcs attribute exclusion
            in `py_library`.
        data: {type}`list[str]` A list of labels to include as part of the `data` attribute in `py_library`.
        enable_implicit_namespace_pkgs: {type}`boolean` generate __init__.py
            files for namespace pkgs.
        native: {type}`native` The native struct for overriding in tests.
        namespace_package_files: {type}`list[str]` A list of labels of files whose
            directories are namespace packages.
        rules: {type}`struct` A struct with references to rules for creating targets.
    """
    dependencies = sorted([normalize_name(d) for d in dependencies])
    tags = sorted(tags)
    data = [] + data

    bins_for_data_label = []

    for ep_dict in entry_points.values():
        kwargs = dict(ep_dict)
        ep_name = kwargs.pop("name")
        ep_target_name = "bin/{}".format(ep_name)
        rules.venv_entry_point(
            name = ep_target_name,
            **kwargs
        )
        bins_for_data_label.append(ep_target_name)
        data.append(ep_target_name)

    existing_bin_names = {ep["name"].lower(): None for ep in entry_points.values()}
    for p in native.glob(["bin/*"], allow_empty = True):
        existing_bin_names[p[len("bin/"):].lower()] = None

    for src_path in native.glob(["rewrite-bin/*"], allow_empty = True):
        script_name = src_path[len("rewrite-bin/"):]
        if script_name.lower() in existing_bin_names:
            continue
        rewrite_target_name = "bin/{}".format(script_name)
        rules.venv_rewrite_shebang(
            name = rewrite_target_name,
            src = src_path,
            package = name,
        )
        bins_for_data_label.append(rewrite_target_name)
        data.append(rewrite_target_name)

    if filegroups == None:
        filegroups = {
            EXTRACTED_WHEEL_FILES: dict(
                include = ["**"],
                exclude = (
                    _BAZEL_REPO_FILE_GLOBS +
                    [sdist_filename] if sdist_filename else []
                ),
            ),
            DIST_INFO_LABEL: dict(
                include = ["site-packages/*.dist-info/**"],
            ),
            DATA_LABEL: dict(
                include = ["data/**", "bin/**", "include/**"],
            ),
        }

    for filegroup_name, glob_kwargs in filegroups.items():
        glob_kwargs = {"allow_empty": True} | glob_kwargs
        srcs = native.glob(**glob_kwargs)
        if filegroup_name == DATA_LABEL:
            srcs = srcs + bins_for_data_label
        native.filegroup(
            name = filegroup_name,
            srcs = srcs,
            visibility = ["//visibility:public"],
        )

    for src, dest in copy_files.items():
        rules.copy_file(
            name = dest + ".copy",
            src = src,
            out = dest,
            visibility = ["//visibility:public"],
        )
        data.append(dest)
    for src, dest in copy_executables.items():
        rules.copy_file(
            name = dest + ".copy",
            src = src,
            out = dest,
            is_executable = True,
            visibility = ["//visibility:public"],
        )
        data.append(dest)

    _config_settings(
        dependencies_with_markers = dependencies_with_markers,
        rules = rules,
        visibility = ["//visibility:private"],
    )
    deps_conditional = {
        d: "is_include_{}_true".format(d)
        for d in dependencies_with_markers
    }

    # If this library is a member of a group, its public label aliases need to
    # point to the group implementation rule not the implementation rules. We
    # also need to mark the implementation rules as visible to the group
    # implementation.
    if group_name and "//:" in dep_template:
        # This is the legacy behaviour where the group library is outside the hub repo
        #
        # It is expected to disappear when we drop WORKSPACE or drop the vendoring of
        # pip_parse `requirements.bzl` in WORKSPACE. The alternative would be to add
        # another argument to the macro, but it is already full of arguments.
        label_tmpl = dep_template.format(
            name = "_config",
            target = normalize_name(group_name) + "_{}",
        ).replace(
            "//:",
            "//_groups:",
        )
        impl_vis = [dep_template.format(
            name = "_config",
            target = "__pkg__",
        ).replace(
            "//:",
            "//_groups:",
        )]

        native.alias(
            name = PY_LIBRARY_PUBLIC_LABEL,
            actual = label_tmpl.format(PY_LIBRARY_PUBLIC_LABEL),
            visibility = ["//visibility:public"],
        )
        native.alias(
            name = WHEEL_FILE_PUBLIC_LABEL,
            actual = label_tmpl.format(WHEEL_FILE_PUBLIC_LABEL),
            visibility = ["//visibility:public"],
        )
        py_library_label = PY_LIBRARY_IMPL_LABEL
        whl_file_label = WHEEL_FILE_IMPL_LABEL

    elif group_name:
        py_library_label = PY_LIBRARY_PUBLIC_LABEL
        whl_file_label = WHEEL_FILE_PUBLIC_LABEL
        impl_vis = [dep_template.format(name = "", target = "__subpackages__")]

    else:
        py_library_label = PY_LIBRARY_PUBLIC_LABEL
        whl_file_label = WHEEL_FILE_PUBLIC_LABEL
        impl_vis = ["//visibility:public"]

    if hasattr(native, "filegroup"):
        native.filegroup(
            name = whl_file_label,
            srcs = [name],
            data = _deps(
                deps = dependencies,
                deps_conditional = deps_conditional,
                tmpl = dep_template.format(name = "{}", target = WHEEL_FILE_PUBLIC_LABEL),
            ),
            visibility = impl_vis,
        )

    if hasattr(rules, "py_library"):
        srcs = native.glob(
            ["site-packages/**/*.py"],
            exclude = srcs_exclude,
            # Empty sources are allowed to support wheels that don't have any
            # pure-Python code, e.g. pymssql, which is written in Cython.
            allow_empty = True,
        )

        # NOTE: pyi files should probably be excluded because they're carried
        # by the pyi_srcs attribute. However, historical behavior included
        # them in data and some tools currently rely on that.
        _data_exclude = [
            "**/*.py",
            "**/*.pyc",
            "**/*.pyc.*",  # During pyc creation, temp files named *.pyc.NNNN are created
        ]
        if sdist_filename:
            _data_exclude.append("**/*.dist-info/RECORD")
        for item in data_exclude:
            if item not in _data_exclude:
                _data_exclude.append(item)

        data = data + native.glob(
            ["site-packages/**/*"],
            exclude = _data_exclude,
            allow_empty = True,
        )

        pyi_srcs = native.glob(
            ["site-packages/**/*.pyi"],
            allow_empty = True,
        )

        if not enable_implicit_namespace_pkgs:
            generated_namespace_package_files = select({
                _IS_VENV_SITE_PACKAGES_YES: [],
                "//conditions:default": rules.create_inits(
                    srcs = srcs + data + pyi_srcs,
                    ignored_dirnames = [],  # If you need to ignore certain folders, you can patch rules_python here to do so.
                    root = "site-packages",
                ),
            })
            namespace_package_files += generated_namespace_package_files
            srcs = srcs + generated_namespace_package_files

        # This is done after create_inits() is called so that the data scheme
        # files don't have such files created in their directories.
        data = data + [DATA_LABEL]

        rules.py_library(
            name = py_library_label,
            srcs = srcs,
            pyi_srcs = pyi_srcs,
            data = data,
            # This makes this directory a top-level in the python import
            # search path for anything that depends on this.
            imports = ["site-packages"],
            deps = _deps(
                deps = dependencies,
                deps_conditional = deps_conditional,
                tmpl = dep_template.format(name = "{}", target = PY_LIBRARY_PUBLIC_LABEL),
            ),
            tags = tags,
            visibility = impl_vis,
            experimental_venvs_site_packages = _VENV_SITE_PACKAGES_FLAG,
            namespace_package_files = namespace_package_files,
        )

def _config_settings(dependencies_with_markers, rules, **kwargs):
    """Generate config settings for the targets.

    Args:
        dependencies_with_markers: {type}`dict[str, str]` The markers to evaluate by
            each dep.
        rules: used for testing
        **kwargs: Extra kwargs to pass to the rule.
    """
    for dep, expression in dependencies_with_markers.items():
        rules.env_marker_setting(
            name = "include_{}".format(dep),
            expression = expression,
            **kwargs
        )

def _deps(deps, deps_conditional, tmpl):
    deps = [tmpl.format(d) for d in sorted(deps)]

    for dep, setting in deps_conditional.items():
        deps = deps + select({
            ":{}".format(setting): [tmpl.format(dep)],
            "//conditions:default": [],
        })

    return deps
