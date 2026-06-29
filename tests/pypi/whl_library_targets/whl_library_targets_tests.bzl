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

""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load(
    "//python/private/pypi:whl_library_targets.bzl",
    "whl_library_targets",
    "whl_library_targets_from_requires",
)  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

def _test_filegroups(env):
    calls = []

    def glob(include, *, exclude = [], allow_empty):
        _ = exclude  # @unused
        env.expect.that_bool(allow_empty).equals(True)
        if include == ["rewrite-bin/*"] or include == ["bin/*"]:
            return []
        return include

    whl_library_targets(
        name = "",
        dep_template = "",
        native = struct(
            filegroup = lambda **kwargs: calls.append(kwargs),
            glob = glob,
        ),
        rules = struct(
            venv_rewrite_shebang = lambda **kwargs: None,
        ),
    )

    env.expect.that_collection(calls, expr = "filegroup calls").contains_exactly([
        {
            "name": "dist_info",
            "srcs": ["site-packages/*.dist-info/**"],
            "visibility": ["//visibility:public"],
        },
        {
            "name": "data",
            "srcs": ["data/**", "bin/**", "include/**"],
            "visibility": ["//visibility:public"],
        },
        {
            "name": "extracted_whl_files",
            "srcs": ["**"],
            "visibility": ["//visibility:public"],
        },
        {
            "name": "whl",
            "srcs": [""],
            "data": [],
            "visibility": ["//visibility:public"],
        },
    ])  # buildifier: @unsorted-dict-items

_tests.append(_test_filegroups)

def _test_copy(env):
    calls = []

    whl_library_targets(
        name = "",
        dep_template = None,
        filegroups = {},
        copy_files = {"file_src": "file_dest"},
        copy_executables = {"exec_src": "exec_dest"},
        native = struct(
            glob = lambda *args, **kwargs: [],
        ),
        rules = struct(
            copy_file = lambda **kwargs: calls.append(kwargs),
            venv_rewrite_shebang = lambda **kwargs: None,
        ),
    )

    env.expect.that_collection(calls).contains_exactly([
        {
            "name": "file_dest.copy",
            "out": "file_dest",
            "src": "file_src",
            "visibility": ["//visibility:public"],
        },
        {
            "is_executable": True,
            "name": "exec_dest.copy",
            "out": "exec_dest",
            "src": "exec_src",
            "visibility": ["//visibility:public"],
        },
    ])

_tests.append(_test_copy)

def _test_whl_and_library_deps_from_requires(env):
    filegroup_calls = []
    py_library_calls = []
    env_marker_setting_calls = []

    m_glob = mocks.glob()

    m_glob.results.append([])  # bin
    m_glob.results.append([])  # rewrite-bin
    m_glob.results.append(["site-packages/foo/SRCS.py"])  # srcs
    m_glob.results.append(["site-packages/foo/DATA.txt"])  # data
    m_glob.results.append(["site-packages/foo/PYI.pyi"])  # pyi

    whl_library_targets_from_requires(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "Foo",
        metadata_version = "0",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [
            "foo",  # this self-edge will be ignored
            "bar",
            "bar-baz; python_version < \"8.2\"",
            "booo",  # this is effectively excluded due to the list below
        ],
        include = ["foo", "bar", "bar_baz"],
        data_exclude = [],
        # Overrides for testing
        filegroups = {},
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            config_setting = lambda **_: None,
            glob = m_glob.glob,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: env_marker_setting_calls.append(kwargs),
            create_inits = lambda *args, **kwargs: ["_create_inits_target"],
            venv_rewrite_shebang = lambda **kwargs: None,
        ),
    )

    env.expect.that_collection(filegroup_calls).contains_exactly([
        {
            "name": "whl",
            "srcs": ["foo-0-py3-none-any.whl"],
            "data": ["@pypi//bar:whl"] + select({
                ":is_include_bar_baz_true": ["@pypi//bar_baz:whl"],
                "//conditions:default": [],
            }),
            "visibility": ["//visibility:public"],
        },
    ])  # buildifier: @unsorted-dict-items

    env.expect.that_collection(py_library_calls).has_size(1)
    if len(py_library_calls) != 1:
        return
    py_library_call = py_library_calls[0]

    env.expect.that_dict(py_library_call).contains_exactly({
        "name": "pkg",
        "srcs": ["site-packages/foo/SRCS.py"] + select({
            Label("//python/config_settings:_is_venvs_site_packages_yes"): [],
            "//conditions:default": ["_create_inits_target"],
        }),
        "pyi_srcs": ["site-packages/foo/PYI.pyi"],
        "data": ["site-packages/foo/DATA.txt", "data"],
        "imports": ["site-packages"],
        "deps": ["@pypi//bar:pkg"] + select({
            ":is_include_bar_baz_true": ["@pypi//bar_baz:pkg"],
            "//conditions:default": [],
        }),
        "tags": ["pypi_name=Foo", "pypi_version=0"],
        "visibility": ["//visibility:public"],
        "experimental_venvs_site_packages": Label("//python/config_settings:venvs_site_packages"),
        "namespace_package_files": [] + select({
            Label("//python/config_settings:_is_venvs_site_packages_yes"): [],
            "//conditions:default": ["_create_inits_target"],
        }),
    })  # buildifier: @unsorted-dict-items

    env.expect.that_collection(m_glob.calls).contains_exactly([
        # bin call
        mocks.glob_call(
            ["bin/*"],
            allow_empty = True,
        ),
        # rewrite-bin call
        mocks.glob_call(
            ["rewrite-bin/*"],
            allow_empty = True,
        ),
        # srcs call
        mocks.glob_call(
            ["site-packages/**/*.py"],
            exclude = [],
            allow_empty = True,
        ),
        # data call
        mocks.glob_call(
            ["site-packages/**/*"],
            exclude = [
                "**/*.py",
                "**/*.pyc",
                "**/*.pyc.*",
            ],
            allow_empty = True,
        ),
        # pyi call
        mocks.glob_call(["site-packages/**/*.pyi"], allow_empty = True),
    ])

    env.expect.that_collection(env_marker_setting_calls).contains_exactly([
        {
            "name": "include_bar_baz",
            "expression": "python_version < \"8.2\"",
            "visibility": ["//visibility:private"],
        },
    ])  # buildifier: @unsorted-dict-items

_tests.append(_test_whl_and_library_deps_from_requires)

def _test_sdist_excludes_record(env):
    py_library_calls = []
    m_glob = mocks.glob()
    m_glob.results.append([])  # bin
    m_glob.results.append([])  # rewrite-bin
    m_glob.results.append([])  # srcs
    m_glob.results.append([])  # data
    m_glob.results.append([])  # pyi

    whl_library_targets(
        name = "foo.whl",
        dep_template = "@pypi_{name}//:{target}",
        sdist_filename = "foo.tar.gz",
        filegroups = {},
        native = struct(
            filegroup = lambda **_: None,
            config_setting = lambda **_: None,
            glob = m_glob.glob,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            create_inits = lambda **kwargs: [],
            venv_rewrite_shebang = lambda **kwargs: None,
        ),
    )

    env.expect.that_collection(m_glob.calls).contains_at_least([
        mocks.glob_call(
            ["site-packages/**/*"],
            exclude = [
                "**/*.py",
                "**/*.pyc",
                "**/*.pyc.*",
                "**/*.dist-info/RECORD",
            ],
            allow_empty = True,
        ),
    ])

_tests.append(_test_sdist_excludes_record)

def whl_library_targets_test_suite(name):
    """create the test suite.

    args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
