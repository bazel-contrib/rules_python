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
"""Tests for RunfilesGroupInfo support (--runfiles_groups)."""

load("@rules_python_internal//:rules_python_config.bzl", rp_config = "config")

# Loaded via the shim, not from @rules_runfiles_group directly: the repo is
# only defined for Bazel versions where the feature is available (see
# runfiles_groups_shim in internal_config_repo.bzl).
load(
    "@rules_python_internal//:runfiles_groups_shim.bzl",
    "ENABLED_FLAG_LABEL",
    "RunfilesGroupInfo",
    "runfiles_groups",
)
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_binary.bzl", "py_binary")
load("//python:py_library.bzl", "py_library")
load("//python/private:runfiles_groups.bzl", "PyRunfilesGroupsInfo")  # buildifier: disable=bzl-visibility

_tests = []

_UPSTREAM_FLAG = str(Label(ENABLED_FLAG_LABEL))
_RULES_PYTHON_FLAG = str(Label("//python/config_settings:runfiles_groups"))

_ENABLED = {_UPSTREAM_FLAG: True}

_APP_GROUP = "rules_python#app"
_RUNTIME_GROUP = "rules_python#runtime"

def _unique_sorted(values):
    return sorted({v: None for v in values}.keys())

def _fold_entries(entries_depset):
    """Flattens an entry depset and folds duplicate names.

    Returns a dict[str, struct(files, symlinks, root_symlinks, entries)]
    keyed by the canonical string form of the group name.
    """
    folded = {}
    for entry in entries_depset.to_list():
        name = runfiles_groups.name_str(entry)
        files = [f.short_path for f in runfiles_groups.files(entry).to_list()]

        # Only the runfiles content form can carry symlinks; a depset[File]
        # content contributes files only.
        if type(entry.content) == "depset":
            symlinks = []
            root_symlinks = []
        else:
            symlinks = [s.path for s in entry.content.symlinks.to_list()]
            root_symlinks = [s.path for s in entry.content.root_symlinks.to_list()]
        if name not in folded:
            folded[name] = struct(
                files = [],
                symlinks = [],
                root_symlinks = [],
                entries = [],
            )
        group = folded[name]
        group.files.extend(files)
        group.symlinks.extend(symlinks)
        group.root_symlinks.extend(root_symlinks)
        group.entries.append(entry)
    return folded

def _find_group(folded, matcher):
    for name in folded:
        if matcher(name):
            return folded[name]
    return None

def _target_group_matcher(target_name):
    return lambda name: name.endswith(":" + target_name)

def _assert_groups_cover_default_runfiles(env, target, folded):
    """Asserts the union of all groups equals default_runfiles exactly."""
    default_runfiles = target[DefaultInfo].default_runfiles

    env.expect.that_collection(
        _unique_sorted([
            path
            for group in folded.values()
            for path in group.files
        ]),
    ).contains_exactly(
        _unique_sorted([
            f.short_path
            for f in default_runfiles.files.to_list()
        ]),
    )
    env.expect.that_collection(
        _unique_sorted([
            path
            for group in folded.values()
            for path in group.root_symlinks
        ]),
    ).contains_exactly(
        _unique_sorted([
            s.path
            for s in default_runfiles.root_symlinks.to_list()
        ]),
    )
    env.expect.that_collection(
        _unique_sorted([
            path
            for group in folded.values()
            for path in group.symlinks
        ]),
    ).contains_exactly(
        _unique_sorted([
            s.path
            for s in default_runfiles.symlinks.to_list()
        ]),
    )

def _test_py_binary_groups(name):
    rt_util.helper_target(
        py_library,
        name = name + "_lib_a",
        srcs = ["liba.py"],
        data = ["data.txt"],
    )
    rt_util.helper_target(
        py_library,
        name = name + "_lib_b",
        srcs = ["libb.py"],
        deps = [name + "_lib_a"],
    )
    native.filegroup(
        name = name + "_fg",
        srcs = ["fg.txt"],
    )
    native.genrule(
        name = name + "_gen",
        outs = [name + "_gen.txt"],
        cmd = "touch $@",
    )
    rt_util.helper_target(
        py_binary,
        name = name + "_subject",
        srcs = ["main.py"],
        main = "main.py",
        deps = [name + "_lib_b"],
        data = [
            name + "_fg",
            name + "_gen",
        ],
        legacy_create_init = 0,
    )
    analysis_test(
        name = name,
        impl = _test_py_binary_groups_impl,
        target = name + "_subject",
        config_settings = _ENABLED,
    )

def _test_py_binary_groups_impl(env, target):
    info = target[RunfilesGroupInfo]
    folded = _fold_entries(info.entries)
    _assert_groups_cover_default_runfiles(env, target, folded)

    names = sorted(folded.keys())
    base_name = target.label.name.removesuffix("_subject")

    env.expect.that_collection(names).contains(_APP_GROUP)
    env.expect.that_collection(names).contains(_RUNTIME_GROUP)
    env.expect.that_str(runfiles_groups.name_str(info.executable_group)).equals(_APP_GROUP)

    # One group per py_library in the dependency graph, named by its label.
    lib_a = _find_group(folded, _target_group_matcher(base_name + "_lib_a"))
    lib_b = _find_group(folded, _target_group_matcher(base_name + "_lib_b"))
    env.expect.that_bool(lib_a != None).equals(True)
    env.expect.that_bool(lib_b != None).equals(True)
    if lib_a:
        env.expect.that_collection(lib_a.files).contains("tests/runfiles_groups/liba.py")

        # Plain data files are part of the library's own group.
        env.expect.that_collection(lib_a.files).contains("tests/runfiles_groups/data.txt")

    # Rule targets in `data` get their own group.
    fg = _find_group(folded, _target_group_matcher(base_name + "_fg"))
    env.expect.that_bool(fg != None).equals(True)

    # The binary's own sources go in the app group.
    env.expect.that_collection(folded[_APP_GROUP].files).contains(
        "tests/runfiles_groups/main.py",
    )

    # The runtime group holds the interpreter and stdlib, ranked first.
    env.expect.that_bool(len(folded[_RUNTIME_GROUP].files) > 0).equals(True)
    runtime_entry = folded[_RUNTIME_GROUP].entries[0]
    env.expect.that_int(runtime_entry.rank).equals(-1000)
    env.expect.that_bool(runtime_entry.do_not_merge).equals(True)
    env.expect.that_str(runtime_entry.kind).equals("foundation")
    app_entry = folded[_APP_GROUP].entries[0]
    env.expect.that_int(app_entry.rank).equals(0)

_tests.append(_test_py_binary_groups)

def _test_py_binary_in_data(name):
    rt_util.helper_target(
        py_binary,
        name = name + "_tool",
        srcs = ["main.py"],
        main = "main.py",
        legacy_create_init = 0,
    )
    rt_util.helper_target(
        py_binary,
        name = name + "_subject",
        srcs = ["main.py"],
        main = "main.py",
        data = [name + "_tool"],
        legacy_create_init = 0,
    )
    analysis_test(
        name = name,
        impl = _test_py_binary_in_data_impl,
        target = name + "_subject",
        config_settings = _ENABLED,
    )

def _test_py_binary_in_data_impl(env, target):
    # The inner binary's app/runtime/venv entries share names with the outer
    # binary's; folding them must keep the union exact.
    info = target[RunfilesGroupInfo]
    folded = _fold_entries(info.entries)
    _assert_groups_cover_default_runfiles(env, target, folded)

    tool_name = target.label.name.removesuffix("_subject") + "_tool"

    # The inner binary's executable ends up in the folded app group.
    env.expect.that_collection(folded[_APP_GROUP].files).contains(
        "tests/runfiles_groups/" + tool_name,
    )

    # The outer binary's executable_group designation is its own.
    env.expect.that_str(runfiles_groups.name_str(info.executable_group)).equals(_APP_GROUP)

_tests.append(_test_py_binary_in_data)

def _test_py_library_private_provider(name):
    rt_util.helper_target(
        py_library,
        name = name + "_lib_a",
        srcs = ["liba.py"],
    )
    rt_util.helper_target(
        py_library,
        name = name + "_subject",
        srcs = ["libb.py"],
        deps = [name + "_lib_a"],
        data = ["data.txt"],
    )
    analysis_test(
        name = name,
        impl = _test_py_library_private_provider_impl,
        target = name + "_subject",
        config_settings = _ENABLED,
    )

def _test_py_library_private_provider_impl(env, target):
    # py_library propagates entries through the private provider only: its
    # sources aren't in its own runfiles, so a public RunfilesGroupInfo
    # could not satisfy the union contract.
    env.expect.that_bool(RunfilesGroupInfo in target).equals(False)
    env.expect.that_bool(PyRunfilesGroupsInfo in target).equals(True)

    folded = _fold_entries(target[PyRunfilesGroupsInfo].entries)
    base_name = target.label.name.removesuffix("_subject")

    own = _find_group(folded, _target_group_matcher(target.label.name))
    dep = _find_group(folded, _target_group_matcher(base_name + "_lib_a"))
    env.expect.that_bool(own != None).equals(True)
    env.expect.that_bool(dep != None).equals(True)
    if own:
        env.expect.that_collection(own.files).contains("tests/runfiles_groups/libb.py")
        env.expect.that_collection(own.files).contains("tests/runfiles_groups/data.txt")
    if dep:
        env.expect.that_collection(dep.files).contains("tests/runfiles_groups/liba.py")

_tests.append(_test_py_library_private_provider)

def _test_pypi_library_group_name(name):
    rt_util.helper_target(
        py_library,
        name = name + "_subject",
        data = ["site-packages/foo_pkg-1.0.dist-info/METADATA"],
    )
    analysis_test(
        name = name,
        impl = _test_pypi_library_group_name_impl,
        target = name + "_subject",
        config_settings = _ENABLED,
    )

def _test_pypi_library_group_name_impl(env, target):
    folded = _fold_entries(target[PyRunfilesGroupsInfo].entries)
    env.expect.that_collection(sorted(folded.keys())).contains(
        "rules_python#pypi/foo_pkg",
    )
    entry = folded["rules_python#pypi/foo_pkg"].entries[0]
    env.expect.that_int(entry.rank).equals(-100)
    env.expect.that_str(entry.kind).equals("third_party")

_tests.append(_test_pypi_library_group_name)

def _test_disabled_by_default(name):
    rt_util.helper_target(
        py_binary,
        name = name + "_subject",
        srcs = ["main.py"],
        main = "main.py",
    )
    analysis_test(
        name = name,
        impl = _test_no_providers_impl,
        target = name + "_subject",
        config_settings = {
            _RULES_PYTHON_FLAG: "auto",
            _UPSTREAM_FLAG: False,
        },
    )

def _test_no_providers_impl(env, target):
    env.expect.that_bool(RunfilesGroupInfo in target).equals(False)
    env.expect.that_bool(PyRunfilesGroupsInfo in target).equals(False)

_tests.append(_test_disabled_by_default)

def _test_rules_python_flag_forces_on(name):
    rt_util.helper_target(
        py_binary,
        name = name + "_subject",
        srcs = ["main.py"],
        main = "main.py",
        legacy_create_init = 0,
    )
    analysis_test(
        name = name,
        impl = _test_rules_python_flag_forces_on_impl,
        target = name + "_subject",
        config_settings = {
            _RULES_PYTHON_FLAG: "enabled",
            _UPSTREAM_FLAG: False,
        },
    )

def _test_rules_python_flag_forces_on_impl(env, target):
    env.expect.that_bool(RunfilesGroupInfo in target).equals(True)

_tests.append(_test_rules_python_flag_forces_on)

def _test_rules_python_flag_forces_off(name):
    rt_util.helper_target(
        py_binary,
        name = name + "_subject",
        srcs = ["main.py"],
        main = "main.py",
    )
    analysis_test(
        name = name,
        impl = _test_no_providers_impl,
        target = name + "_subject",
        config_settings = {
            _RULES_PYTHON_FLAG: "disabled",
            _UPSTREAM_FLAG: True,
        },
    )

_tests.append(_test_rules_python_flag_forces_off)

def runfiles_groups_test_suite(name):
    test_suite(
        name = name,
        # The providers require Bazel 9+ (see runfiles_groups_shim in
        # internal_config_repo.bzl).
        tests = _tests if rp_config.bazel_9_or_later else [],
    )
