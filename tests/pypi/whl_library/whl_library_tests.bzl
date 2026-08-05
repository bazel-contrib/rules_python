# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Tests for //python/private/pypi:whl_library.bzl

These tests verify the dispatching logic in the ``whl_library`` function,
ensuring the correct underlying rule is invoked (directly or via ``maybe``)
with the right arguments for each code path.

The ``rules`` parameter of ``whl_library`` is used to inject mock rule functions
that record their calls instead of creating actual repository rules.
"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")

# buildifier: disable=bzl-visibility
load("//python/private/pypi:whl_library.bzl", "whl_library")

_tests = []

def _mock_rules(calls):
    def _whl_archive(**kwargs):
        calls.append(struct(rule = "whl_archive", kwargs = dict(kwargs)))
        return kwargs.get("name")

    def _pip_archive(**kwargs):
        calls.append(struct(rule = "pip_archive", kwargs = dict(kwargs)))
        return kwargs.get("name")

    def _whl_deps_library(**kwargs):
        calls.append(struct(rule = "whl_deps_library", kwargs = dict(kwargs)))
        return kwargs.get("name")

    return struct(
        whl_archive = _whl_archive,
        pip_archive = _pip_archive,
        whl_deps_library = _whl_deps_library,
    )

def _calls_for(calls, rule_name):
    return [c for c in calls if c.rule == rule_name]

def _test_whl_file_reuse_path(env):
    calls = []
    whl_library(
        name = "test_repo",
        rules = _mock_rules(calls),
        whl_file = "@some_wheels//:pkg-1.0-py3-none-any.whl",
        requirement = "pkg==1.0",
    )
    whl_archive_calls = _calls_for(calls, "whl_archive")
    env.expect.that_int(len(whl_archive_calls)).equals(1)
    env.expect.that_dict(whl_archive_calls[0].kwargs).contains_exactly({
        "name": "w_pkg_1_0_py3_none_any",
        "requirement": "pkg==1.0",
        "whl_file": "@some_wheels//:pkg-1.0-py3-none-any.whl",
    })
    deps_calls = _calls_for(calls, "whl_deps_library")
    env.expect.that_int(len(deps_calls)).equals(1)
    env.expect.that_dict(deps_calls[0].kwargs).contains_exactly({
        "metadata_file": "@w_pkg_1_0_py3_none_any//:metadata.json",
        "name": "test_repo",
    })

_tests.append(_test_whl_file_reuse_path)

def _test_urls_reuse_path(env):
    calls = []
    whl_library(
        name = "test_repo",
        rules = _mock_rules(calls),
        whl_file = None,
        urls = ["https://example.com/pkg-1.0-py3-none-any.whl"],
        filename = "pkg-1.0-py3-none-any.whl",
        requirement = "pkg==1.0",
        config_load = "@pypi//:config.bzl",
    )
    whl_archive_calls = _calls_for(calls, "whl_archive")
    env.expect.that_int(len(whl_archive_calls)).equals(1)
    env.expect.that_dict(whl_archive_calls[0].kwargs).contains_exactly({
        "filename": "pkg-1.0-py3-none-any.whl",
        "name": "w_pkg_1_0_py3_none_any",
        "requirement": "pkg==1.0",
        "urls": ["https://example.com/pkg-1.0-py3-none-any.whl"],
        "whl_file": None,
    })
    deps_calls = _calls_for(calls, "whl_deps_library")
    env.expect.that_int(len(deps_calls)).equals(1)
    env.expect.that_dict(deps_calls[0].kwargs).contains_exactly({
        "config_load": "@pypi//:config.bzl",
        "metadata_file": "@w_pkg_1_0_py3_none_any//:metadata.json",
        "name": "test_repo",
    })

_tests.append(_test_urls_reuse_path)

def _test_annotation_no_reuse(env):
    calls = []
    whl_library(
        name = "test_repo",
        rules = _mock_rules(calls),
        whl_file = None,
        urls = ["https://example.com/pkg-1.0-py3-none-any.whl"],
        filename = "pkg-1.0-py3-none-any.whl",
        requirement = "pkg[extra]==1.0",
        annotation = "@some_repo//:pkg.annotation.json",
    )
    whl_archive_calls = _calls_for(calls, "whl_archive")
    env.expect.that_int(len(whl_archive_calls)).equals(1)
    env.expect.that_dict(whl_archive_calls[0].kwargs).contains_exactly({
        "annotation": "@some_repo//:pkg.annotation.json",
        "filename": "pkg-1.0-py3-none-any.whl",
        "name": "test_repo",
        "requirement": "pkg[extra]==1.0",
        "urls": ["https://example.com/pkg-1.0-py3-none-any.whl"],
        "whl_file": None,
    })
    env.expect.that_int(len(_calls_for(calls, "whl_deps_library"))).equals(0)

_tests.append(_test_annotation_no_reuse)

def _test_whl_patches_no_reuse(env):
    calls = []
    whl_library(
        name = "test_repo",
        rules = _mock_rules(calls),
        whl_file = None,
        urls = ["https://example.com/pkg-1.0-py3-none-any.whl"],
        filename = "pkg-1.0-py3-none-any.whl",
        requirement = "pkg==1.0",
        whl_patches = {"//patches:foo.patch": "json"},
    )
    whl_archive_calls = _calls_for(calls, "whl_archive")
    env.expect.that_int(len(whl_archive_calls)).equals(1)
    env.expect.that_dict(whl_archive_calls[0].kwargs).contains_exactly({
        "filename": "pkg-1.0-py3-none-any.whl",
        "name": "test_repo",
        "requirement": "pkg==1.0",
        "urls": ["https://example.com/pkg-1.0-py3-none-any.whl"],
        "whl_file": None,
        "whl_patches": {"//patches:foo.patch": "json"},
    })
    env.expect.that_int(len(_calls_for(calls, "whl_deps_library"))).equals(0)

_tests.append(_test_whl_patches_no_reuse)

def _test_pip_archive_path(env):
    calls = []
    whl_library(
        name = "test_repo",
        rules = _mock_rules(calls),
        requirement = "pkg==1.0",
        config_load = "@pypi//:config.bzl",
    )
    pip_archive_calls = _calls_for(calls, "pip_archive")
    env.expect.that_int(len(pip_archive_calls)).equals(1)
    env.expect.that_dict(pip_archive_calls[0].kwargs).contains_exactly({
        "config_load": "@pypi//:config.bzl",
        "name": "test_repo",
        "requirement": "pkg==1.0",
    })
    env.expect.that_int(len(_calls_for(calls, "whl_archive"))).equals(0)

_tests.append(_test_pip_archive_path)

def _test_extras_not_passed_when_empty(env):
    calls = []
    whl_library(
        name = "test_repo",
        rules = _mock_rules(calls),
        whl_file = None,
        urls = ["https://example.com/pkg-1.0-py3-none-any.whl"],
        filename = "pkg-1.0-py3-none-any.whl",
        requirement = "pkg==1.0",
        config_load = "@pypi//:config.bzl",
    )
    deps_calls = _calls_for(calls, "whl_deps_library")
    env.expect.that_int(len(deps_calls)).equals(1)
    env.expect.that_collection(
        deps_calls[0].kwargs.keys(),
    ).contains_none_of(["extras"])

_tests.append(_test_extras_not_passed_when_empty)

def _test_extras_passed_when_non_empty(env):
    calls = []
    whl_library(
        name = "test_repo",
        rules = _mock_rules(calls),
        whl_file = None,
        urls = ["https://example.com/pkg-1.0-py3-none-any.whl"],
        filename = "pkg-1.0-py3-none-any.whl",
        requirement = "pkg[foo,bar]==1.0",
        config_load = "@pypi//:config.bzl",
    )
    deps_calls = _calls_for(calls, "whl_deps_library")
    env.expect.that_int(len(deps_calls)).equals(1)
    env.expect.that_collection(
        deps_calls[0].kwargs["extras"],
    ).contains_exactly(["foo", "bar"])

_tests.append(_test_extras_passed_when_non_empty)

def _test_python_interpreter_excluded(env):
    calls = []
    whl_library(
        name = "test_repo",
        rules = _mock_rules(calls),
        whl_file = None,
        urls = ["https://example.com/pkg-1.0-py3-none-any.whl"],
        filename = "pkg-1.0-py3-none-any.whl",
        requirement = "pkg==1.0",
        config_load = "@pypi//:config.bzl",
        python_interpreter = "python3",
        python_interpreter_target = "@python//:python",
    )
    whl_archive_calls = _calls_for(calls, "whl_archive")
    env.expect.that_int(len(whl_archive_calls)).equals(1)
    env.expect.that_collection(
        whl_archive_calls[0].kwargs.keys(),
    ).contains_none_of(["python_interpreter", "python_interpreter_target"])

_tests.append(_test_python_interpreter_excluded)

def _test_config_load_excluded_from_extract_args(env):
    calls = []
    whl_library(
        name = "test_repo",
        rules = _mock_rules(calls),
        whl_file = None,
        urls = ["https://example.com/pkg-1.0-py3-none-any.whl"],
        filename = "pkg-1.0-py3-none-any.whl",
        requirement = "pkg==1.0",
        config_load = "@pypi//:config.bzl",
        dep_template = "@pypi%{name}//:{{target}}",
    )
    whl_archive_calls = _calls_for(calls, "whl_archive")
    env.expect.that_int(len(whl_archive_calls)).equals(1)
    env.expect.that_collection(
        whl_archive_calls[0].kwargs.keys(),
    ).contains_none_of(["config_load", "dep_template"])

_tests.append(_test_config_load_excluded_from_extract_args)

def _test_wheel_reuse_across_different_extras(env):
    calls = []
    whl_library(
        name = "pkg_foo_repo",
        rules = _mock_rules(calls),
        whl_file = None,
        urls = ["https://example.com/pkg-1.0-py3-none-any.whl"],
        filename = "pkg-1.0-py3-none-any.whl",
        requirement = "pkg[foo]==1.0",
    )
    whl_library(
        name = "pkg_bar_repo",
        rules = _mock_rules(calls),
        whl_file = None,
        urls = ["https://example.com/pkg-1.0-py3-none-any.whl"],
        filename = "pkg-1.0-py3-none-any.whl",
        requirement = "pkg[bar]==1.0",
    )
    whl_archive_calls = _calls_for(calls, "whl_archive")
    env.expect.that_int(len(whl_archive_calls)).equals(2)
    env.expect.that_str(whl_archive_calls[0].kwargs["name"]).equals("w_pkg_1_0_py3_none_any")
    env.expect.that_str(whl_archive_calls[1].kwargs["name"]).equals("w_pkg_1_0_py3_none_any")

    deps_calls = _calls_for(calls, "whl_deps_library")
    env.expect.that_int(len(deps_calls)).equals(2)
    env.expect.that_dict(deps_calls[0].kwargs).contains_exactly({
        "extras": ["foo"],
        "metadata_file": "@w_pkg_1_0_py3_none_any//:metadata.json",
        "name": "pkg_foo_repo",
    })
    env.expect.that_dict(deps_calls[1].kwargs).contains_exactly({
        "extras": ["bar"],
        "metadata_file": "@w_pkg_1_0_py3_none_any//:metadata.json",
        "name": "pkg_bar_repo",
    })

_tests.append(_test_wheel_reuse_across_different_extras)

def whl_library_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )
