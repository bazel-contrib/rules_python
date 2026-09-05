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
"""Setup a python-build-standalone based toolchain."""

load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//python:py_runtime.bzl", "py_runtime")
load("//python:py_runtime_pair.bzl", "py_runtime_pair")
load("//python/cc:py_cc_toolchain.bzl", "py_cc_toolchain")
load(":common_labels.bzl", "labels")
load(":py_exec_tools_toolchain.bzl", "py_exec_tools_toolchain")
load(":util.bzl", "list_add_unique")
load(":version.bzl", "version")
load(":zip_stdlib.bzl", "zip_stdlib")

_IS_FREETHREADED_YES = str(
    Label("//python/config_settings:_is_py_freethreaded_yes"),
)
_IS_FREETHREADED_NO = str(
    Label("//python/config_settings:_is_py_freethreaded_no"),
)
_IS_ZIP_STDLIB_YES = str(
    Label("//python/config_settings:_is_zip_stdlib_yes"),
)
_IS_ZIP_STDLIB_NO = str(
    Label("//python/config_settings:_is_zip_stdlib_no"),
)

def _define_zip_stdlib(
        *,
        name,
        files_exclude,
        version_dict,
        tags = None,
        unix_stdlib_dir = None):
    """Defines a zip_stdlib target for the standard library.

    Args:
        name: {type}`str` The target name.
        files_exclude: {type}`list[str]` File patterns to exclude from zipping.
        version_dict: {type}`dict[str, str]` Version dictionary containing
            major and minor versions.
        tags: {type}`list[str]` optional list of tags to apply to the target.
        unix_stdlib_dir: {type}`str` Base directory of standard library on Unix
            (e.g. "lib/python3.11").

    Returns:
        {type}`str` The label of the generated zip_stdlib target.
    """
    tags = tags or []
    windows_stdlib_dir = "Lib"
    unix_stdlib_dir = (
        unix_stdlib_dir or "lib/python{major}.{minor}".format(**version_dict)
    )
    zip_out = select({
        ":is_freethreaded_windows": (
            "python{major}{minor}t.zip".format(**version_dict)
        ),
        labels.PLATFORMS_OS_WINDOWS: (
            "python{major}{minor}.zip".format(**version_dict)
        ),
        _IS_FREETHREADED_YES: (
            "lib/python{major}{minor}t.zip".format(**version_dict)
        ),
        "//conditions:default": (
            "lib/python{major}{minor}.zip".format(**version_dict)
        ),
    })
    zip_strip_prefix = select({
        ":is_freethreaded_windows": windows_stdlib_dir,
        labels.PLATFORMS_OS_WINDOWS: windows_stdlib_dir,
        _IS_FREETHREADED_YES: unix_stdlib_dir + "t",
        "//conditions:default": unix_stdlib_dir,
    })
    zip_srcs = select({
        labels.PLATFORMS_OS_WINDOWS: native.glob(
            include = [windows_stdlib_dir + "/**"],
            exclude = files_exclude + [
                "**/site-packages/**",
                windows_stdlib_dir + "/**/test/**",
                windows_stdlib_dir + "/**/tests/**",
            ],
            allow_empty = True,
        ),
        "//conditions:default": native.glob(
            include = [
                unix_stdlib_dir + "*/**",
            ],
            exclude = files_exclude + [
                "**/site-packages/**",
                "**/lib-dynload/**",
            ],
            allow_empty = True,
        ),
    })

    zip_stdlib_tags = ["manual"]
    if tags:
        list_add_unique(zip_stdlib_tags, [tags])

    zip_stdlib(
        name = name,
        out = zip_out,
        srcs = zip_srcs,
        strip_prefix = zip_strip_prefix,
        tags = zip_stdlib_tags,
    )
    return ":" + name

def define_hermetic_runtime_toolchain_impl(
        *,
        name,
        extra_files_glob_include,
        extra_files_glob_exclude,
        python_version,
        python_bin,
        coverage_tool,
        tags = None):
    """Define a toolchain implementation for a python-build-standalone repo.

    It expected this macro is called in the top-level package of an extracted
    python-build-standalone repository. See
    python/private/python_repositories.bzl for how it is invoked.

    Args:
        name: {type}`str` name used for tools to identify the invocation.
        extra_files_glob_include: {type}`list[str]` additional glob include
            patterns for the target runtime files (the one included in
            binaries).
        extra_files_glob_exclude: {type}`list[str]` additional glob exclude
            patterns for the target runtime files.
        python_version: {type}`str` The Python version, in `major.minor.micro`
            format.
        python_bin: {type}`str` The path to the Python binary within the
            repository.
        coverage_tool: {type}`str` optional target to the coverage tool to
            use.
        tags: {type}`list[str]` optional list of tags to apply to generated
            targets.
    """
    _ = name  # @unused
    tags = tags or []
    manual_tags = ["manual"]
    if tags:
        list_add_unique(manual_tags, [tags])
    version_info = version.parse(python_version)
    version_dict = {
        "major": version_info.release[0],
        "minor": version_info.release[1],
    }
    windows_stdlib_dir = "Lib"
    unix_stdlib_dir = "lib/python{major}.{minor}".format(**version_dict)
    unix_stdlib_dir_glob = unix_stdlib_dir + "*"
    files_include = [
        "bin/**",
        "extensions/**",
        "include/**",
        "libs/**",
        "share/**",
    ]
    files_include += extra_files_glob_include
    files_exclude = [
        # Unused shared libraries. `python` executable and the `:libpython` target
        # depend on `libpython{python_version}.so.1.0`.
        "lib/libpython{major}.{minor}*.so".format(**version_dict),
        # static libraries
        "lib/**/*.a",
        # tests for the standard libraries.
        unix_stdlib_dir_glob + "/**/test/**",
        unix_stdlib_dir_glob + "/**/tests/**",
        windows_stdlib_dir + "/**/test/**",
        windows_stdlib_dir + "/**/tests/**",
        # During pyc creation, temp files named *.pyc.NNN are created
        "**/__pycache__/*.pyc.*",
    ]
    files_exclude += extra_files_glob_exclude

    native.filegroup(
        name = "files_landmark",
        # CPython's calculate_path (getpath.py/getpath.c) requires os.py on disk
        # as a landmark file to determine sys.prefix and the standard library
        # directory during interpreter initialization.
        srcs = select({
            labels.PLATFORMS_OS_WINDOWS: native.glob(
                include = [windows_stdlib_dir + "/os.py"],
                exclude = files_exclude,
                allow_empty = True,
            ),
            "//conditions:default": native.glob(
                include = [unix_stdlib_dir_glob + "/os.py"],
                exclude = files_exclude,
                allow_empty = True,
            ),
        }),
        tags = manual_tags,
    )
    native.filegroup(
        name = "files_base",
        srcs = [
            ":files_landmark",
        ] + select({
            labels.PLATFORMS_OS_WINDOWS: native.glob(
                include = files_include,
                allow_empty = True,
                exclude = files_exclude + [
                    windows_stdlib_dir + "/**",
                ],
            ),
            "//conditions:default": native.glob(
                include = files_include,
                allow_empty = True,
                exclude = files_exclude + [
                    unix_stdlib_dir_glob + "/**/*.py",
                    unix_stdlib_dir_glob + "/*.py",
                    unix_stdlib_dir_glob + "/*.json",
                    unix_stdlib_dir_glob + "/site-packages/**",
                ],
            ),
        }),
        tags = manual_tags,
    )
    native.filegroup(
        name = "files_unzipped_stdlib",
        srcs = select({
            labels.PLATFORMS_OS_WINDOWS: native.glob(
                include = [windows_stdlib_dir + "/**"],
                allow_empty = True,
                exclude = files_exclude,
            ),
            "//conditions:default": native.glob(
                include = [
                    unix_stdlib_dir_glob + "/**/*.py",
                    unix_stdlib_dir_glob + "/*.py",
                    unix_stdlib_dir_glob + "/*.json",
                ],
                allow_empty = True,
                exclude = files_exclude,
            ),
        }),
        tags = manual_tags,
    )
    native.filegroup(
        name = "files",
        srcs = [":files_base"] + select({
            _IS_ZIP_STDLIB_YES: [],
            _IS_ZIP_STDLIB_NO: [":files_unzipped_stdlib"],
        }),
        tags = tags,
    )
    cc_import(
        name = "interface",
        interface_library = select({
            _IS_FREETHREADED_YES: "libs/python{major}{minor}t.lib".format(**version_dict),
            _IS_FREETHREADED_NO: "libs/python{major}{minor}.lib".format(**version_dict),
        }),
        system_provided = True,
        tags = tags,
    )
    cc_import(
        name = "abi3_interface",
        interface_library = select({
            _IS_FREETHREADED_YES: "libs/python3t.lib",
            _IS_FREETHREADED_NO: "libs/python3.lib",
        }),
        system_provided = True,
        tags = tags,
    )

    native.filegroup(
        name = "includes",
        srcs = native.glob(
            ["include/**/*.h"],
            allow_empty = True,
        ),
        tags = tags,
    )
    cc_library(
        name = "python_headers_abi3",
        deps = select({
            "@bazel_tools//src/conditions:windows": [":abi3_interface"],
            "//conditions:default": None,
        }),
        hdrs = [":includes"],
        includes = [
            "include",
        ] + select({
            _IS_FREETHREADED_YES: [
                "include/python{major}.{minor}t".format(**version_dict),
            ],
            _IS_FREETHREADED_NO: [
                "include/python{major}.{minor}".format(**version_dict),
                "include/python{major}.{minor}m".format(**version_dict),
            ],
        }),
        tags = tags,
    )
    cc_library(
        name = "python_headers",
        hdrs = [":includes"],
        deps = [":python_headers_abi3"] + select({
            "@bazel_tools//src/conditions:windows": [":interface"],
            "//conditions:default": [],
        }),
        tags = tags,
    )
    native.config_setting(
        name = "is_freethreaded_linux",
        flag_values = {
            Label("//python/config_settings:py_freethreaded"): "yes",
        },
        constraint_values = [
            "@platforms//os:linux",
        ],
        visibility = ["//visibility:private"],
    )
    native.config_setting(
        name = "is_freethreaded_osx",
        flag_values = {
            Label("//python/config_settings:py_freethreaded"): "yes",
        },
        constraint_values = [
            "@platforms//os:osx",
        ],
        visibility = ["//visibility:private"],
    )
    native.config_setting(
        name = "is_freethreaded_windows",
        flag_values = {
            Label("//python/config_settings:py_freethreaded"): "yes",
        },
        constraint_values = [
            "@platforms//os:windows",
        ],
        visibility = ["//visibility:private"],
    )

    cc_library(
        name = "libpython",
        hdrs = [":includes"],
        srcs = select({
            ":is_freethreaded_linux": [
                "lib/libpython{major}.{minor}t.so".format(**version_dict),
                "lib/libpython{major}.{minor}t.so.1.0".format(**version_dict),
            ],
            ":is_freethreaded_osx": [
                "lib/libpython{major}.{minor}t.dylib".format(**version_dict),
            ],
            ":is_freethreaded_windows": [
                "python3t.dll",
                "python{major}{minor}t.dll".format(**version_dict),
                "libs/python{major}{minor}t.lib".format(**version_dict),
                "libs/python3t.lib",
            ],
            "@platforms//os:macos": ["lib/libpython{major}.{minor}.dylib".format(**version_dict)],
            "@platforms//os:windows": [
                "python3.dll",
                "python{major}{minor}.dll".format(**version_dict),
                "libs/python{major}{minor}.lib".format(**version_dict),
                "libs/python3.lib",
            ],
            "//conditions:default": [
                "lib/libpython{major}.{minor}.so".format(**version_dict),
                "lib/libpython{major}.{minor}.so.1.0".format(**version_dict),
            ],
        }),
        tags = tags,
    )

    native.exports_files(["python", python_bin])

    # Used to only download coverage toolchain when the coverage is collected by
    # bazel.
    native.config_setting(
        name = "coverage_enabled",
        values = {"collect_code_coverage": "true"},
        visibility = ["//visibility:private"],
    )
    if not version_info.pre:
        releaselevel = "final"
    else:
        releaselevel = {
            "a": "alpha",
            "b": "beta",
            "rc": "candidate",
        }.get(version_info.pre[0])

    zip_stdlib_target = _define_zip_stdlib(
        name = "zip_stdlib",
        files_exclude = files_exclude,
        tags = tags,
        unix_stdlib_dir = unix_stdlib_dir,
        version_dict = version_dict,
    )

    native.filegroup(
        name = "windows_zip_stdlib",
        srcs = select({
            _IS_ZIP_STDLIB_YES: [zip_stdlib_target],
            _IS_ZIP_STDLIB_NO: [],
        }),
        tags = manual_tags,
    )

    py_runtime(
        name = "py3_runtime",
        files = [
            ":files",
        ] + select({
            _IS_ZIP_STDLIB_YES: [zip_stdlib_target],
            _IS_ZIP_STDLIB_NO: [],
        }),
        interpreter = python_bin,
        interpreter_version_info = {
            "major": str(version_info.release[0]),
            "micro": str(version_info.release[2]),
            "minor": str(version_info.release[1]),
            "releaselevel": releaselevel,
            "serial": str(version_info.pre[1]) if version_info.pre else "0",
        },
        coverage_tool = select({
            # Convert empty string to None
            ":coverage_enabled": coverage_tool or None,
            "//conditions:default": None,
        }),
        python_version = "PY3",
        implementation_name = "cpython",
        # See https://peps.python.org/pep-3147/ for pyc tag infix format
        pyc_tag = select({
            _IS_FREETHREADED_YES: (
                "cpython-{major}{minor}t".format(**version_dict)
            ),
            _IS_FREETHREADED_NO: (
                "cpython-{major}{minor}".format(**version_dict)
            ),
        }),
        # On Windows, a symlink-style venv requires supporting .dll files.
        venv_bin_files = select({
            labels.PLATFORMS_OS_WINDOWS: [
                ":windows_zip_stdlib",
            ] + native.glob(
                include = [
                    "*.dll",
                ],
                # This must be true because glob empty-ness is checked
                # during loading phase, before select() filters it out.
                allow_empty = True,
            ),
            "//conditions:default": [],
        }),
        zip_stdlib = select({
            _IS_ZIP_STDLIB_YES: zip_stdlib_target,
            _IS_ZIP_STDLIB_NO: None,
        }),
        tags = tags,
    )

    py_runtime_pair(
        name = "python_runtimes",
        py2_runtime = None,
        py3_runtime = ":py3_runtime",
        tags = tags,
    )

    py_cc_toolchain(
        name = "py_cc_toolchain",
        headers = ":python_headers",
        headers_abi3 = ":python_headers_abi3",
        # TODO #3155: add libctl, libtk
        libs = ":libpython",
        python_version = python_version,
        tags = tags,
    )

    py_exec_tools_toolchain(
        name = "py_exec_tools_toolchain",
        # This macro is called in another repo: use Label() to ensure it
        # resolves in the rules_python context.
        precompiler = Label("//tools/precompiler:precompiler"),
        tags = tags,
    )
