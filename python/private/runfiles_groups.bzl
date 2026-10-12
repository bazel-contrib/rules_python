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
"""Runfiles group describers of the Python rules, for rules_runfiles_group.

A packaging rule (a container image rule, say) walks a binary with an aspect and
asks each target's describer which runfiles it adds and which attributes it
merges runfiles in from. The Python rules point their `_runfiles_group_describer`
attribute at the describers below.

Only `//python/private:BUILD.bazel` loads this file; the rules refer to the
describers by label. With Bazel 8's autoloads, rules_python loading
rules_runfiles_group from the files that define the rules is a load cycle.

A library's group holds what it contributes to a consuming binary: the files the
binary takes from its PyInfo, plus its plain data files.
"""

load("@rules_runfiles_group//runfiles_group:lib.bzl", "runfiles_groups")
load(":attributes.bzl", "PycCollectionAttr")
load(":common.bzl", "is_py_source", "py_info_runfiles_files")
load(":flags.bzl", "PyiDepsToRunfilesFlag")
load(":py_executable.bzl", "get_runtime_files")
load(":py_executable_info.bzl", "PyExecutableInfo")
load(":py_info.bzl", "PyInfo")
load(":py_internal.bzl", "py_internal")
load(":py_library.bzl", "get_package_and_version")
load(":reexports.bzl", "BuiltinPyInfo")
load(":toolchain_types.bzl", TOOLCHAIN_TYPE = "TARGET_TOOLCHAIN_TYPE")

# Stamped on every group, so Python groups stay together when a packager has to
# merge groups to fit a layer limit.
_MERGE_AFFINITY = "rules_python"

# The interpreter and standard library, shared by every binary in a configuration.
_RUNTIME_GROUP = "rules_python#runtime"

# Libraries from PyPI are named by package: whl_library's repository names are an
# implementation detail.
_PYPI_GROUP_PREFIX = "rules_python#pypi/"

def _pyc_collection_enabled(ctx, pyc_collection = PycCollectionAttr.INHERIT):
    # PycCollectionAttr only reads these two attributes.
    return PycCollectionAttr.is_pyc_collection_enabled(struct(attr = struct(
        pyc_collection = pyc_collection,
        _precompile_flag = ctx.rule.attr._precompile_flag,
    )))

def _is_file(target):
    # A source file owns itself, a generated file is owned by the rule that
    # generates it, and a rule target owns its own outputs.
    files = target[DefaultInfo].files
    if not py_internal.is_singleton_depset(files):
        return False
    file = files.to_list()[0]
    return (file.owner == target.label) == file.is_source

def _is_empty(runfiles):
    return not (runfiles.files or runfiles.symlinks or runfiles.root_symlinks)

def _py_info_files(target, pyc_collection_enabled):
    if PyInfo in target:
        return py_info_runfiles_files(target[PyInfo], pyc_collection_enabled)
    if BuiltinPyInfo != None and BuiltinPyInfo in target:
        return py_info_runfiles_files(target[BuiltinPyInfo], pyc_collection_enabled)
    return []

def _kind(label):
    return "first_party" if label.repo_name == "" else "third_party"

def _own_files(target, ctx, pyc_collection_enabled):
    """The files a target itself puts into a consuming binary's runfiles."""
    info = target[PyInfo]

    # Sources that aren't .py files (directories, .pyc files) are outputs, but
    # never runfiles.
    sources = {f: None for f in info.direct_original_sources.to_list()}
    direct = [
        f
        for f in target[DefaultInfo].files.to_list()
        if f not in sources or is_py_source(f)
    ]
    transitive = []
    if pyc_collection_enabled:
        transitive.append(info.direct_implicit_pyc_files)
    else:
        direct.extend([f for f in sources if is_py_source(f)])

    # Plain files in `data` belong to the target's own group (and so to each
    # target listing them); rule targets get groups of their own.
    for dep in ctx.rule.attr.data:
        if _is_file(dep):
            direct.append(dep[DefaultInfo].files.to_list()[0])
    return depset(direct, transitive = transitive)

def _dep_fallback(ctx, dep, py_outputs):
    content = _py_info_files(dep, _pyc_collection_enabled(ctx))
    if py_outputs and not content:
        content.append(depset([f for f in dep[DefaultInfo].files.to_list() if is_py_source(f)]))
    runfiles = dep[DefaultInfo].default_runfiles
    if not _is_empty(runfiles):
        content.append(runfiles)
    if not content:
        return None
    return runfiles_groups.entry(name = dep.label, content = runfiles_groups.union(ctx, content))

def _library_dep_fallback(ctx, dep):
    # py_library adds the .py outputs of a dep without PyInfo to its own PyInfo.
    return _dep_fallback(ctx, dep, py_outputs = True)

def _executable_dep_fallback(ctx, dep):
    return _dep_fallback(ctx, dep, py_outputs = False)

def _data_fallback(ctx, dep):
    # Plain files are in the merging target's own group.
    default_info = dep[DefaultInfo]
    if _is_file(dep) or (not default_info.files and _is_empty(default_info.data_runfiles)):
        return None
    content = runfiles_groups.union(ctx, [default_info.files, default_info.data_runfiles])
    return runfiles_groups.entry(name = dep.label, content = content)

def _srcs_fallback(_ctx, dep):
    runfiles = dep[DefaultInfo].default_runfiles
    if _is_file(dep) or _is_empty(runfiles):
        return None
    return runfiles_groups.entry(name = dep.label, content = runfiles)

def _describe_py_library(target, ctx):
    pyc_collection_enabled = _pyc_collection_enabled(ctx)
    content = _own_files(target, ctx, pyc_collection_enabled)

    # With pyi_deps_to_runfiles, a binary takes the files of pyi_deps from
    # this target's PyInfo, but not their runfiles.
    if PyiDepsToRunfilesFlag.is_enabled(struct(attr = ctx.rule.attr, var = ctx.var)):
        content = depset(transitive = [content] + [
            files
            for dep in ctx.rule.attr.pyi_deps
            for files in _py_info_files(dep, pyc_collection_enabled)
        ])

    package, _ = get_package_and_version(ctx.rule.files.data)
    if package:
        name = _PYPI_GROUP_PREFIX + package
        kind = "third_party"
    else:
        name = ctx.label
        kind = _kind(ctx.label)
    return runfiles_groups.node(
        add = [runfiles_groups.entry(
            name = name,
            content = content,
            kind = kind,
            rank = runfiles_groups.RANK_SHARED_DEPS if kind == "third_party" else runfiles_groups.RANK_EXECUTABLE,
            weight = len(ctx.rule.files.srcs) + len(ctx.rule.files.data),
            merge_affinity = _MERGE_AFFINITY,
        )] if content else [],
        merge_from = [
            runfiles_groups.merge_from("data", fallback = _data_fallback),
            runfiles_groups.merge_from("deps", fallback = _library_dep_fallback),
            runfiles_groups.merge_from("srcs", fallback = _srcs_fallback),
        ],
    )

py_library_runfiles_group_describer = runfiles_groups.make_describer_rule(
    describe = _describe_py_library,
)

def _describe_py_executable(target, ctx):
    info = target[PyExecutableInfo]
    pyc_collection_enabled = _pyc_collection_enabled(ctx, ctx.rule.attr.pyc_collection)
    content = [
        _own_files(target, ctx, pyc_collection_enabled),
        depset([f for f in (info.build_data_file, info.stage2_bootstrap) if f]),
    ]
    content.extend([rf for rf in (info.venv_runfiles, info.venv_interpreter_runfiles) if rf])

    # Two cases where the binary's group takes its dependencies:
    # * The legacy __init__.py files: they're generated for every directory in
    #   the runfiles, the runtime's included. Checking for them is cheap unless
    #   they exist.
    # * A pyc selection that differs from the configuration's, which is the one
    #   dependencies describe their files with.
    if info.app_runfiles.empty_filenames:
        content.append(info.runfiles_without_exe)
        merge_from = []
    elif pyc_collection_enabled != _pyc_collection_enabled(ctx):
        content.append(info.app_runfiles)
        merge_from = ["_runfiles_group_python_runtime"]
    else:
        merge_from = [
            "_runfiles_group_python_runtime",
            runfiles_groups.merge_from("_debugger_flag", fallback = _executable_dep_fallback),
            runfiles_groups.merge_from("data", fallback = _data_fallback),
            runfiles_groups.merge_from("deps", fallback = _executable_dep_fallback),
            runfiles_groups.merge_from("srcs", fallback = _srcs_fallback),
        ]

    return runfiles_groups.node(
        add = [runfiles_groups.entry(
            name = ctx.label,
            content = runfiles_groups.union(ctx, content),
            kind = _kind(ctx.label),
            merge_affinity = _MERGE_AFFINITY,
        )],
        merge_from = merge_from,
        executable_group = ctx.label,
    )

py_executable_runfiles_group_describer = runfiles_groups.make_describer_rule(
    describe = _describe_py_executable,
)

def _describe_python_runtime(target, _ctx):
    files = target[DefaultInfo].files
    return runfiles_groups.node(add = [runfiles_groups.entry(
        name = _RUNTIME_GROUP,
        content = files,
        kind = "foundation",
        rank = runfiles_groups.RANK_FOUNDATION,
        do_not_merge = True,
        merge_affinity = _MERGE_AFFINITY,
    )] if files else [])

python_runtime_runfiles_group_describer = runfiles_groups.make_describer_rule(
    describe = _describe_python_runtime,
)

def _python_runtime_runfiles_impl(ctx):
    return [DefaultInfo(files = get_runtime_files(ctx))]

python_runtime_runfiles = rule(
    implementation = _python_runtime_runfiles_impl,
    doc = """\
The runtime files a binary puts into its runfiles, as one runfiles group.

Every binary merges in the same target, so a packager builds the group once per
configuration rather than once per binary.
""",
    attrs = {
        "_runfiles_group_attrs": attr.string_list(default = []),
        "_runfiles_group_describer": attr.label(
            default = ":python_runtime_runfiles_group_describer",
        ),
    },
    toolchains = [TOOLCHAIN_TYPE],
)
