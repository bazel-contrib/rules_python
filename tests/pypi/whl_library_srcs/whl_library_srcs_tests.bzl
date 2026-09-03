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
load("//python/private/pypi:whl_library_srcs.bzl", "whl_library_srcs")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

def _test_filegroups(env):
    calls = []

    def glob(include, *, exclude = [], allow_empty):
        _ = exclude  # @unused
        env.expect.that_bool(allow_empty).equals(True)
        if include in [["rewrite-bin/*"], ["bin/*"], ["rewrite-record/*/RECORD"]]:
            return []
        return include

    whl_library_srcs(
        name = "",
        native = struct(
            filegroup = lambda **kwargs: calls.append(kwargs),
            glob = glob,
        ),
        rules = struct(
            venv_rewrite_shebang = lambda **kwargs: None,
            gen_wheel_record = lambda **kwargs: None,
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
            "name": "whl_file",
            "srcs": [""],
            "visibility": ["//visibility:public"],
        },
    ])  # buildifier: @unsorted-dict-items

_tests.append(_test_filegroups)

def _test_copy(env):
    calls = []

    whl_library_srcs(
        name = "",
        filegroups = {},
        copy_files = {"file_src": "file_dest"},
        copy_executables = {"exec_src": "exec_dest"},
        native = struct(
            glob = lambda *args, **kwargs: [],
        ),
        rules = struct(
            copy_file = lambda **kwargs: calls.append(kwargs),
            venv_rewrite_shebang = lambda **kwargs: None,
            gen_wheel_record = lambda **kwargs: None,
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

def _test_sdist_excludes_record(env):
    py_library_calls = []
    m_glob = mocks.glob()
    m_glob.results.append([])  # bin
    m_glob.results.append([])  # rewrite-bin
    m_glob.results.append([])  # rewrite-record
    m_glob.results.append([])  # srcs
    m_glob.results.append([])  # data
    m_glob.results.append([])  # pyi

    whl_library_srcs(
        name = "foo.whl",
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
            gen_wheel_record = lambda **kwargs: None,
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

def _test_exclude_bazel_files(env):
    # Regression test: the `extracted_whl_files` glob must always exclude the
    # Bazel repo files, even when the wheel is not built from an sdist.
    for sdist_filename in [None, "foo.tar.gz"]:
        m_glob = mocks.glob()
        m_glob.results.append([])  # bin
        m_glob.results.append([])  # rewrite-bin
        m_glob.results.append([])  # rewrite-record
        m_glob.results.append([])  # extracted_whl_files
        m_glob.results.append([])  # dist_info
        m_glob.results.append([])  # data

        whl_library_srcs(
            name = "foo.whl",
            sdist_filename = sdist_filename,
            native = struct(
                filegroup = lambda **_: None,
                glob = m_glob.glob,
            ),
            rules = struct(
                venv_rewrite_shebang = lambda **kwargs: None,
                gen_wheel_record = lambda **kwargs: None,
            ),
        )

        expected_exclude = [
            "BUILD",
            "BUILD.bazel",
            "REPO.bazel",
            "WORKSPACE",
            "WORKSPACE.bzlmod",
            "WORKSPACE.bazel",
        ]
        if sdist_filename:
            expected_exclude.append(sdist_filename)

        env.expect.that_collection(m_glob.calls).contains_exactly([
            mocks.glob_call(["bin/*"], allow_empty = True),
            mocks.glob_call(["rewrite-bin/*"], allow_empty = True),
            mocks.glob_call(["rewrite-record/*/RECORD"], allow_empty = True),
            mocks.glob_call(
                include = ["**"],
                exclude = expected_exclude,
                allow_empty = True,
            ),
            mocks.glob_call(
                include = ["site-packages/*.dist-info/**"],
                allow_empty = True,
            ),
            mocks.glob_call(
                include = ["data/**", "bin/**", "include/**"],
                allow_empty = True,
            ),
        ])

_tests.append(_test_exclude_bazel_files)

def whl_library_srcs_test_suite(name):
    """create the test suite.

    args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
