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

def _test_external_whl_file(env):
    calls = []
    whl_library_srcs(
        name = "example-1.0-py3-none-any.whl",
        whl_file = "@example_whl//:example-1.0-py3-none-any.whl",
        native = struct(
            filegroup = lambda **kwargs: calls.append(kwargs),
            glob = lambda *args, **kwargs: [],
        ),
        rules = struct(),
    )
    wheel = [call for call in calls if call["name"] == "whl_file"][0]
    env.expect.that_collection(wheel["srcs"]).contains_exactly([
        "@example_whl//:example-1.0-py3-none-any.whl",
    ])
    extracted = [call for call in calls if call["name"] == "extracted_whl_files"][0]
    env.expect.that_collection(extracted["srcs"]).contains_exactly([])

_tests.append(_test_external_whl_file)

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

def _test_pyi_srcs_includes_py_typed(env):
    py_library_calls = []
    m_glob = mocks.glob()
    m_glob.results.append([])  # bin
    m_glob.results.append([])  # rewrite-bin
    m_glob.results.append([])  # rewrite-record
    m_glob.results.append([])  # srcs
    m_glob.results.append([])  # data
    m_glob.results.append([
        "site-packages/foo/__init__.pyi",
        "site-packages/foo/py.typed",
    ])  # pyi

    whl_library_srcs(
        name = "foo.whl",
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
            ["site-packages/**/*.pyi", "site-packages/**/py.typed"],
            allow_empty = True,
        ),
    ])
    env.expect.that_int(len(py_library_calls)).equals(1)
    env.expect.that_collection(py_library_calls[0]["pyi_srcs"]).contains_exactly([
        "site-packages/foo/__init__.pyi",
        "site-packages/foo/py.typed",
    ])

_tests.append(_test_pyi_srcs_includes_py_typed)

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

def _test_default_mode_data_order(env):
    py_library_calls = []
    m_glob = mocks.glob()
    m_glob.results.append([])  # bin/*
    m_glob.results.append(["rewrite-bin/rewritten_script"])  # rewrite-bin/*
    m_glob.results.append(["rewrite-record/foo-1.0.dist-info/RECORD"])  # rewrite-record/*/RECORD
    m_glob.results.append([])  # srcs
    m_glob.results.append(["site-packages/foo/asset.dat"])  # site-packages/**/* data
    m_glob.results.append([])  # pyi

    whl_library_srcs(
        name = "foo.whl",
        filegroups = {},
        data = ["user_data"],
        entry_points = {
            "ep_cli": {
                "group": "console_scripts",
                "module": "foo.cli",
                "name": "ep_cli",
                "object": "main",
            },
        },
        copy_files = {"@ext//:file_src": "file_dest"},
        copy_executables = {"@ext//:exec_src": "exec_dest"},
        native = struct(
            filegroup = lambda **_: None,
            glob = m_glob.glob,
        ),
        rules = struct(
            copy_file = lambda **_: None,
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            create_inits = lambda **_: [],
            venv_entry_point = lambda **_: None,
            venv_rewrite_shebang = lambda **_: None,
            gen_wheel_record = lambda **_: None,
        ),
    )

    env.expect.that_int(len(py_library_calls)).equals(1)
    env.expect.that_collection(py_library_calls[0]["data"]).contains_exactly([
        "user_data",
        "bin/ep_cli",
        "bin/rewritten_script",
        "record",
        "file_dest",
        "exec_dest",
        "site-packages/foo/asset.dat",
        "data",
    ]).in_order()

_tests.append(_test_default_mode_data_order)

def _test_action_install(env):
    filegroup_calls = []
    copy_calls = []
    entry_point_calls = []
    py_wheel_library_calls = []

    whl_library_srcs(
        name = "foo-1.0-py3-none-any.whl",
        action_install = True,
        sdist_filename = "foo-1.0.tar.gz",
        extracted_files = [
            "bin/bin_tool",
            "data/etc/cfg.txt",
            "include/foo/foo.h",
            "site-packages/foo-1.0.dist-info/METADATA",
            "site-packages/foo/__init__.py",
        ],
        has_entry_points_txt = True,
        namespace_package_files = ["site-packages/foo/__init__.py"],
        shebang_scripts = ["shebang_tool"],
        srcs_exclude = ["foo/exclude.py"],
        data_exclude = ["foo/exclude.dat"],
        copy_files = {"@ext//:file_src": "file_dest"},
        copy_executables = {"@ext//:exec_src": "exec_dest"},
        entry_points = {
            "ep_cli": {
                "group": "console_scripts",
                "module": "foo.cli",
                "name": "ep_cli",
                "object": "main",
            },
        },
        tags = ["pypi_name=foo", "pypi_version=1.0"],
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            glob = lambda *args, **kwargs: env.fail("glob should not be called when action_install=True"),
        ),
        rules = struct(
            copy_file = lambda **kwargs: copy_calls.append(kwargs),
            venv_entry_point = lambda **kwargs: entry_point_calls.append(kwargs),
            py_wheel_library = lambda **kwargs: py_wheel_library_calls.append(kwargs),
        ),
    )

    env.expect.that_int(len(entry_point_calls)).equals(1)
    env.expect.that_int(len(copy_calls)).equals(2)
    env.expect.that_collection(filegroup_calls).contains_exactly([
        {
            "name": "whl_file",
            "srcs": ["foo-1.0-py3-none-any.whl"],
            "visibility": ["//visibility:public"],
        },
        {
            "name": "extracted_whl_files",
            "srcs": ["srcs"],
            "visibility": ["//visibility:public"],
        },
        {
            "name": "dist_info",
            "srcs": ["entry_points.txt"],
            "visibility": ["//visibility:public"],
        },
        {
            "name": "data",
            "srcs": ["srcs", "bin/ep_cli"],
            "visibility": ["//visibility:public"],
        },
    ])
    env.expect.that_int(len(py_wheel_library_calls)).equals(1)
    call = py_wheel_library_calls[0]
    env.expect.that_str(call["name"]).equals("srcs")
    env.expect.that_str(call["wheel"]).equals("foo-1.0-py3-none-any.whl")
    env.expect.that_collection(call["extracted_files"]).contains_exactly([
        "bin/bin_tool",
        "data/etc/cfg.txt",
        "include/foo/foo.h",
        "site-packages/foo-1.0.dist-info/METADATA",
        "site-packages/foo/__init__.py",
    ])
    env.expect.that_collection(call["namespace_package_files"]).contains_exactly([
        "site-packages/foo/__init__.py",
    ])
    env.expect.that_collection(call["shebang_scripts"]).contains_exactly(["shebang_tool"])
    env.expect.that_collection(call["srcs_exclude"]).contains_exactly(["foo/exclude.py"])
    env.expect.that_collection(call["data_exclude"]).contains_exactly(["foo/exclude.dat"])
    env.expect.that_collection(call["data"]).contains_exactly([
        "bin/ep_cli",
        "file_dest",
        "exec_dest",
    ])

    ext_filegroup_calls = []
    ext_py_wheel_library_calls = []
    whl_library_srcs(
        name = "foo-1.0-py3-none-any.whl",
        whl_file = "@foo_whl//:foo-1.0-py3-none-any.whl",
        action_install = True,
        native = struct(
            filegroup = lambda **kwargs: ext_filegroup_calls.append(kwargs),
            glob = lambda *args, **kwargs: env.fail("glob should not be called when action_install=True"),
        ),
        rules = struct(
            py_wheel_library = lambda **kwargs: ext_py_wheel_library_calls.append(kwargs),
        ),
    )
    ext_whl_fg = [c for c in ext_filegroup_calls if c["name"] == "whl_file"][0]
    env.expect.that_collection(ext_whl_fg["srcs"]).contains_exactly([
        "@foo_whl//:foo-1.0-py3-none-any.whl",
    ])
    ext_dist_info_fg = [c for c in ext_filegroup_calls if c["name"] == "dist_info"][0]
    env.expect.that_collection(ext_dist_info_fg["srcs"]).contains_exactly([])
    env.expect.that_str(ext_py_wheel_library_calls[0]["wheel"]).equals(
        "@foo_whl//:foo-1.0-py3-none-any.whl",
    )

_tests.append(_test_action_install)

def _test_action_install_fails_on_custom_filegroups(env):
    errors = []
    whl_library_srcs(
        name = "foo-1.0-py3-none-any.whl",
        action_install = True,
        filegroups = {"custom_fg": {"include": ["site-packages/**"]}},
        _fail = errors.append,
    )
    env.expect.that_int(len(errors)).equals(1)
    env.expect.that_str(errors[0]).contains("custom glob-based 'filegroups'")
    env.expect.that_str(errors[0]).contains("custom_fg")

_tests.append(_test_action_install_fails_on_custom_filegroups)

def _test_action_install_fails_on_wheel_copy_files(env):
    errors = []
    whl_library_srcs(
        name = "foo-1.0-py3-none-any.whl",
        action_install = True,
        extracted_files = ["site-packages/foo/__init__.py"],
        shebang_scripts = ["shebang_tool"],
        copy_files = {"site-packages/foo/__init__.py": "copied.py"},
        copy_executables = {"bin/shebang_tool": "copied_tool"},
        _fail = errors.append,
    )
    env.expect.that_int(len(errors)).equals(1)
    env.expect.that_str(errors[0]).contains("reference wheel-extracted paths")
    env.expect.that_str(errors[0]).contains("bin/shebang_tool")
    env.expect.that_str(errors[0]).contains("site-packages/foo/__init__.py")

_tests.append(_test_action_install_fails_on_wheel_copy_files)

def whl_library_srcs_test_suite(name):
    """create the test suite.

    args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
