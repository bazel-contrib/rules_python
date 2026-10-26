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
    "//python/private/pypi:py_wheel_extract_files.bzl",
    "match_wheel_glob",
    "wheel_extract_prefix",
    "wheel_glob",
)  # buildifier: disable=bzl-visibility
load("//python/private/pypi:whl_library_srcs.bzl", "whl_library_srcs")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:whl_library_targets.bzl", "whl_library_targets")  # buildifier: disable=bzl-visibility
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
    env.expect.that_int(len(py_wheel_library_calls)).equals(2)
    env.expect.that_str(py_wheel_library_calls[0]["name"]).equals("_wheel_install")
    env.expect.that_str(py_wheel_library_calls[0]["wheel"]).equals("foo-1.0-py3-none-any.whl")
    env.expect.that_collection(py_wheel_library_calls[0]["data"]).contains_exactly([])
    call = py_wheel_library_calls[1]
    env.expect.that_str(call["name"]).equals("srcs")
    env.expect.that_str(call["wheel"]).equals(":_wheel_install")
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
    env.expect.that_int(len(ext_py_wheel_library_calls)).equals(2)
    env.expect.that_str(ext_py_wheel_library_calls[0]["name"]).equals("_wheel_install")
    env.expect.that_str(ext_py_wheel_library_calls[0]["wheel"]).equals(
        "@foo_whl//:foo-1.0-py3-none-any.whl",
    )
    env.expect.that_str(ext_py_wheel_library_calls[1]["name"]).equals("srcs")
    env.expect.that_str(ext_py_wheel_library_calls[1]["wheel"]).equals(":_wheel_install")

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
    env.expect.that_str(errors[0]).contains("py_wheel_extract_files")

_tests.append(_test_action_install_fails_on_custom_filegroups)

def _test_action_install_internal_copy_and_filegroups(env):
    filegroup_calls = []
    copy_calls = []
    extract_calls = []
    py_wheel_library_calls = []

    whl_library_srcs(
        name = "foo-1.0-py3-none-any.whl",
        action_install = True,
        extracted_files = [
            "bin/bin_tool",
            "data/etc/cfg.txt",
            "include/foo/foo.h",
            "site-packages/foo-1.0.dist-info/METADATA",
            "site-packages/foo/__init__.py",
        ],
        filegroups = {
            "custom_fg": [
                "data/**/*.txt",
                "include/**/*.h",
            ],
        },
        copy_files = {
            "@ext_repo//:ext.txt": "ext_dest.txt",
            "data/etc/cfg.txt": "copied_cfg.txt",
        },
        copy_executables = {
            "bin/bin_tool": "copied_tool",
        },
        tags = ["pypi_name=foo", "pypi_version=1.0"],
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            glob = lambda *args, **kwargs: env.fail("glob should not be called when action_install=True"),
        ),
        rules = struct(
            copy_file = lambda **kwargs: copy_calls.append(kwargs),
            py_wheel_extract_files = lambda **kwargs: extract_calls.append(kwargs),
            py_wheel_library = lambda **kwargs: py_wheel_library_calls.append(kwargs),
        ),
    )

    # Note: data/etc/cfg.txt is already extracted by _wheel_extract_0 for copy_files,
    # so _wheel_extract_1 for custom_fg only extracts include/foo/foo.h (de-duplicated!).
    env.expect.that_collection(extract_calls).contains_exactly([
        {
            "name": "_wheel_extract_0",
            "outs": ["_extracted/data/etc/cfg.txt"],
            "paths": ["data/etc/cfg.txt"],
            "visibility": ["//visibility:private"],
            "wheel_library": ":_wheel_install",
        },
        {
            "is_executable": True,
            "name": "_wheel_extract_exec_0",
            "outs": ["_extracted_exec/bin/bin_tool"],
            "paths": ["bin/bin_tool"],
            "visibility": ["//visibility:private"],
            "wheel_library": ":_wheel_install",
        },
        {
            "name": "_wheel_extract_1",
            "outs": ["_extracted/include/foo/foo.h"],
            "paths": ["include/foo/foo.h"],
            "visibility": ["//visibility:private"],
            "wheel_library": ":_wheel_install",
        },
    ])
    env.expect.that_collection(copy_calls).contains_exactly([
        {
            "name": "ext_dest.txt.copy",
            "out": "ext_dest.txt",
            "src": "@ext_repo//:ext.txt",
            "visibility": ["//visibility:public"],
        },
        {
            "name": "copied_cfg.txt.copy",
            "out": "copied_cfg.txt",
            "src": ":_extracted/data/etc/cfg.txt",
            "visibility": ["//visibility:public"],
        },
        {
            "is_executable": True,
            "name": "copied_tool.copy",
            "out": "copied_tool",
            "src": ":_extracted_exec/bin/bin_tool",
            "visibility": ["//visibility:public"],
        },
    ])
    env.expect.that_collection(filegroup_calls).contains_at_least([
        {
            "name": "custom_fg",
            "srcs": [
                ":_extracted/data/etc/cfg.txt",
                ":_extracted/include/foo/foo.h",
            ],
            "visibility": ["//visibility:public"],
        },
    ])
    env.expect.that_int(len(py_wheel_library_calls)).equals(2)
    env.expect.that_str(py_wheel_library_calls[0]["name"]).equals("_wheel_install")
    env.expect.that_str(py_wheel_library_calls[0]["wheel"]).equals("foo-1.0-py3-none-any.whl")
    env.expect.that_collection(py_wheel_library_calls[0]["data"]).contains_exactly([])
    env.expect.that_collection(py_wheel_library_calls[0]["visibility"]).contains_exactly(["//visibility:public"])
    env.expect.that_str(py_wheel_library_calls[1]["name"]).equals("srcs")
    env.expect.that_str(py_wheel_library_calls[1]["wheel"]).equals(":_wheel_install")
    env.expect.that_collection(py_wheel_library_calls[1]["data"]).contains_exactly([
        "ext_dest.txt",
        "copied_cfg.txt",
        "copied_tool",
    ])

_tests.append(_test_action_install_internal_copy_and_filegroups)

def _test_wheel_glob_dedup_and_sdist_failure(env):
    rules_by_name = {
        "srcs": {
            "extracted_files": [
                "site-packages/torch/lib/libc10.so",
                "site-packages/torch/lib/libtorch_cpu.so",
                "site-packages/torch/include/torch.h",
            ],
            "kind": "py_wheel_library",
            "shebang_scripts": [],
        },
    }
    extract_calls = []

    def record_extract(**kwargs):
        extract_calls.append(kwargs)
        rules_by_name[kwargs["name"]] = kwargs

    mock_native = struct(
        existing_rule = lambda name: rules_by_name.get(name),
    )

    # First call: pattern pair (.so vs .dylib) where only .so exists.
    c10 = wheel_glob(
        [
            "site-packages/torch/lib/libc10.so",
            "site-packages/torch/lib/libc10.dylib",
        ],
        native = mock_native,
        extract_rule = record_extract,
    )
    env.expect.that_collection(c10).contains_exactly([
        ":_extracted/site-packages/torch/lib/libc10.so",
    ])

    # Second call: wildcard over all .so files; libc10.so is already extracted
    # so only libtorch_cpu.so should be added in _wheel_extract_1.
    all_so = wheel_glob(
        ["site-packages/torch/**/*.so"],
        native = mock_native,
        extract_rule = record_extract,
    )
    env.expect.that_collection(all_so).contains_exactly([
        ":_extracted/site-packages/torch/lib/libc10.so",
        ":_extracted/site-packages/torch/lib/libtorch_cpu.so",
    ])
    env.expect.that_int(len(extract_calls)).equals(2)
    env.expect.that_collection(extract_calls[0]["paths"]).contains_exactly([
        "site-packages/torch/lib/libc10.so",
    ])
    env.expect.that_collection(extract_calls[1]["paths"]).contains_exactly([
        "site-packages/torch/lib/libtorch_cpu.so",
    ])

    # Sdist-built wheel fails with a clear message (both with site_paths and empty site_paths).
    sdist_errors = []
    wheel_glob(
        ["site-packages/**"],
        native = struct(
            existing_rule = lambda name: {"kind": "py_wheel_library", "site_paths": ["pkg"]} if name == "srcs" else None,
        ),
        _fail = sdist_errors.append,
    )
    env.expect.that_int(len(sdist_errors)).equals(1)
    env.expect.that_str(sdist_errors[0]).contains("cannot be used with an action-built sdist")

    empty_site_paths_sdist_errors = []
    wheel_glob(
        ["site-packages/**"],
        native = struct(
            existing_rule = lambda name: {"kind": "py_wheel_library", "site_paths": [], "wheel": ":whldir"} if name == "srcs" else ({"kind": "py_sdist_wheel"} if name == "whldir" else None),
        ),
        _fail = empty_site_paths_sdist_errors.append,
    )
    env.expect.that_int(len(empty_site_paths_sdist_errors)).equals(1)
    env.expect.that_str(empty_site_paths_sdist_errors[0]).contains("cannot be used with an action-built sdist")

    # Invalid exclude_directories and invalid glob patterns fail clearly.
    excl_dir_errors = []
    wheel_glob(
        ["site-packages/**"],
        exclude_directories = 2,
        files = ["site-packages/a.py"],
        _fail = excl_dir_errors.append,
    )
    env.expect.that_int(len(excl_dir_errors)).equals(1)
    env.expect.that_str(excl_dir_errors[0]).contains("exclude_directories")

    for bad_pat in ["", "/abs", "trail/", "a//b", "../up", "a/./b", "a/**b", "a/b**"]:
        pat_errors = []
        match_wheel_glob(["a/b.py"], [bad_pat], _fail = pat_errors.append)
        env.expect.that_int(len(pat_errors)).equals(1)

    # Default mode merges custom filegroups with built-in extracted_whl_files, dist_info, data.
    fg_calls = []
    whl_library_srcs(
        name = "foo.whl",
        filegroups = {"custom_fg": ["site-packages/**/*.so"]},
        native = struct(
            filegroup = lambda **kwargs: fg_calls.append(kwargs["name"]),
            glob = lambda *args, **kwargs: [],
        ),
        rules = struct(
            venv_rewrite_shebang = lambda **kwargs: None,
            gen_wheel_record = lambda **kwargs: None,
        ),
    )
    env.expect.that_collection(fg_calls).contains_exactly([
        "whl_file",
        "extracted_whl_files",
        "dist_info",
        "data",
        "custom_fg",
    ])

    # Default mode wheel_glob delegates to native.glob while excluding repo bookkeeping files.
    default_glob_excludes = []
    wheel_glob(
        ["*"],
        exclude = ["custom_excl.txt"],
        native = struct(
            existing_rule = lambda name: (
                {"kind": "py_library"} if name == "srcs" else (
                    {"srcs": [":foo-1.0-py3-none-any.whl"]} if name == "whl_file" else None
                )
            ),
            glob = lambda include, exclude = [], **kwargs: default_glob_excludes.extend(exclude) or include,
        ),
    )
    env.expect.that_collection(default_glob_excludes).contains_at_least([
        "BUILD",
        "BUILD.bazel",
        "MODULE.bazel",
        "REPO.bazel",
        "WORKSPACE",
        "WORKSPACE.bzlmod",
        "WORKSPACE.bazel",
        "metadata.json",
        "wheel_files.bzl",
        "*.whl",
        "foo-1.0-py3-none-any.whl",
        "custom_excl.txt",
    ])
    env.expect.that_str(wheel_extract_prefix(native = mock_native)).equals("_extracted/")
    env.expect.that_str(wheel_extract_prefix(is_executable = True, native = mock_native)).equals("_extracted_exec/")
    env.expect.that_str(
        wheel_extract_prefix(
            native = struct(existing_rule = lambda name: {"kind": "py_library"} if name == "srcs" else None),
        ),
    ).equals("")

_tests.append(_test_wheel_glob_dedup_and_sdist_failure)

def _test_action_sdist(env):
    py_sdist_wheel_calls = []
    py_wheel_library_calls = []
    env_marker_setting_calls = []
    filegroup_calls = []

    whl_library_targets(
        name = "foo-1.0.sdist_build.whl",
        action_install = True,
        sdist_filename = "foo-1.0.tar.gz",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        include = ["foo", "hatchling", "cython", "tomli", "setuptools_scm"],
        sdist = {
            "add_libdir_to_library_search_path": True,
            "build_deps": [
                "@@+pip+pypi//setuptools_scm:pkg",
                "@@//third_party/flit_core:flit_core",
                "@@//:custom_builder_bundle",
            ],
            "build_requires": [
                "setuptools>=61",
                "setuptools-scm>=8",
                "flit-core>=3.8",
                "some-custom-backend>=1.0",
                "hatchling>=1.18",
                "tomli>=1.0; python_version < '3.11'",
                "cython; python_version >= '3.8'",
                "cffi; implementation_name == 'pypy'",
                "nonexistent; extra == 'dev'",
            ],
            "config_settings": {"--build-option": "--pure"},
            "environment": {"FOO_ENV": "1"},
            "pre_build_patch_strips": [1],
            "pre_build_patches": ["//patches:pre.patch"],
            "site_paths": ["foo"],
        },
        tags = ["pypi_name=foo", "pypi_version=1.0"],
        native = struct(
            alias = lambda **_: None,
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            glob = lambda *args, **kwargs: env.fail("glob should not be called in action mode"),
        ),
        rules = struct(
            env_marker_setting = lambda **kwargs: env_marker_setting_calls.append(kwargs),
            py_sdist_wheel = lambda **kwargs: py_sdist_wheel_calls.append(kwargs),
            py_wheel_library = lambda **kwargs: py_wheel_library_calls.append(kwargs),
        ),
    )

    env.expect.that_int(len(py_sdist_wheel_calls)).equals(1)
    sdist_call = py_sdist_wheel_calls[0]
    env.expect.that_str(sdist_call["name"]).equals("foo-1.0.sdist_build.whl")
    env.expect.that_str(sdist_call["sdist"]).equals("foo-1.0.tar.gz")
    env.expect.that_dict(sdist_call).contains_at_least({
        "add_libdir_to_library_search_path": True,
        "build_deps": [
            "@@+pip+pypi//setuptools_scm:pkg",
            "@@//third_party/flit_core:flit_core",
            "@@//:custom_builder_bundle",
            "@pypi//hatchling:pkg",
        ] + select({
            ":is_include_sdist_build_cython_true": ["@pypi//cython:pkg"],
            "//conditions:default": [],
        }),
        "config_settings": {"--build-option": "--pure"},
        "environment": {"FOO_ENV": "1"},
        "pre_build_patch_strips": [1],
        "pre_build_patches": ["//patches:pre.patch"],
    })
    env.expect.that_collection(env_marker_setting_calls).contains_exactly([
        {
            "expression": 'python_version >= "3.8"',
            "name": "include_sdist_build_cython",
            "visibility": ["//visibility:private"],
        },
    ])
    env.expect.that_collection(filegroup_calls).contains_at_least([
        {
            "name": "whl_file",
            "srcs": ["foo-1.0.sdist_build.whl"],
            "visibility": ["//visibility:public"],
        },
        {
            "name": "whldir",
            "output_group": "whldir",
            "srcs": ["foo-1.0.sdist_build.whl"],
            "visibility": ["//visibility:public"],
        },
        {
            "name": "dist_info",
            "output_group": "dist_info",
            "srcs": [":srcs"],
            "visibility": ["//visibility:public"],
        },
    ])

    env.expect.that_int(len(py_wheel_library_calls)).equals(1)
    whl_call = py_wheel_library_calls[0]
    env.expect.that_str(whl_call["name"]).equals("srcs")
    env.expect.that_str(whl_call["wheel"]).equals("foo-1.0.sdist_build.whl")
    env.expect.that_collection(whl_call["site_paths"]).contains_exactly(["foo"])

    # Verify sdist fails with guidance naming py_wheel_extract_files on custom filegroups
    # or wheel-internal copy_files.
    sdist_fg_errors = []
    whl_library_srcs(
        name = "foo-1.0.sdist_build.whl",
        action_install = True,
        sdist_filename = "foo-1.0.tar.gz",
        sdist = {"site_paths": ["foo"]},
        filegroups = {"custom_fg": ["site-packages/**"]},
        _fail = sdist_fg_errors.append,
    )
    env.expect.that_int(len(sdist_fg_errors)).equals(1)
    env.expect.that_str(sdist_fg_errors[0]).contains("py_wheel_extract_files")

    sdist_copy_errors = []
    whl_library_srcs(
        name = "foo-1.0.sdist_build.whl",
        action_install = True,
        sdist_filename = "foo-1.0.tar.gz",
        sdist = {"site_paths": ["foo"]},
        copy_files = {"site-packages/foo/cfg.txt": "copied_cfg.txt"},
        _fail = sdist_copy_errors.append,
    )
    env.expect.that_int(len(sdist_copy_errors)).equals(1)
    env.expect.that_str(sdist_copy_errors[0]).contains("py_wheel_extract_files")

_tests.append(_test_action_sdist)

def whl_library_srcs_test_suite(name):
    """create the test suite.

    args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
