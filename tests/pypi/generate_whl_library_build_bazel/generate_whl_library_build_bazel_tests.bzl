# Copyright 2023 The Bazel Authors. All rights reserved.
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
    "//python/private/pypi:generate_whl_library_build_bazel.bzl",
    "generate_sdist_wheel_files_bzl",
    "generate_wheel_files_bzl",
    "generate_whl_library_build_bazel",
    "parse_sdist_extra_pip_args",
)  # buildifier: disable=bzl-visibility

_tests = []

def _test_all_workspace(env):
    want = """\
load("@pypi//:config.bzl", "packages")
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_targets")
load("@rules_python//python/private/pypi:whl_package_metadata.bzl", "whl_package_metadata")

package(default_visibility = ["//visibility:public"])

whl_library_targets(
    copy_executables = {
        "exec_src": "exec_dest",
    },
    copy_files = {
        "file_src": "file_dest",
    },
    data = ["extra_target"],
    data_exclude = [
        "exclude_via_attr",
        "data_exclude_all",
    ],
    dep_template = "@pypi//{name}:{target}",
    group_deps = [
        "foo",
        "fox",
        "qux",
    ],
    group_name = "qux",
    include = packages,
    metadata_name = "foo",
    name = "foo.whl",
    requires_dist = [
        "foo",
        "bar-baz",
        "qux",
    ],
    srcs_exclude = ["srcs_exclude_all"],
    tags = [
        "pypi_name=foo",
        "pypi_version=0",
    ],
)

whl_package_metadata(
    distribution = "foo",
    file_name = "foo.whl",
    version = "0",
)

# SOMETHING SPECIAL AT THE END
"""
    actual = generate_whl_library_build_bazel(
        metadata_version = "0",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        name = "foo.whl",
        requires_dist = ["foo", "bar-baz", "qux"],
        data_exclude = ["exclude_via_attr"],
        annotation = struct(
            copy_files = {"file_src": "file_dest"},
            copy_executables = {"exec_src": "exec_dest"},
            data = ["extra_target"],
            data_exclude_glob = ["data_exclude_all"],
            srcs_exclude_glob = ["srcs_exclude_all"],
            additive_build_content = """# SOMETHING SPECIAL AT THE END""",
        ),
        config_load = "@pypi//:config.bzl",
        group_name = "qux",
        group_deps = ["foo", "fox", "qux"],
        purl = {"distribution": "foo", "file_name": "foo.whl", "version": "0"},
    )
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

_tests.append(_test_all_workspace)

def _test_all(env):
    want = """\
load("@pypi//:config.bzl", "packages")
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_targets")
load("@rules_python//python/private/pypi:whl_package_metadata.bzl", "whl_package_metadata")

package(default_visibility = ["//visibility:public"])

whl_library_targets(
    copy_executables = {
        "exec_src": "exec_dest",
    },
    copy_files = {
        "file_src": "file_dest",
    },
    data = ["extra_target"],
    data_exclude = [
        "exclude_via_attr",
        "data_exclude_all",
    ],
    dep_template = "@pypi//{name}:{target}",
    group_deps = [
        "foo",
        "fox",
        "qux",
    ],
    group_name = "qux",
    include = packages,
    metadata_name = "foo",
    name = "foo.whl",
    requires_dist = [
        "foo",
        "bar-baz",
        "qux",
    ],
    srcs_exclude = ["srcs_exclude_all"],
    tags = [
        "pypi_name=foo",
        "pypi_version=0",
    ],
)

whl_package_metadata(
    distribution = "foo",
    file_name = "foo.whl",
    version = "0",
)

# SOMETHING SPECIAL AT THE END
"""
    actual = generate_whl_library_build_bazel(
        metadata_version = "0",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        name = "foo.whl",
        requires_dist = ["foo", "bar-baz", "qux"],
        data_exclude = ["exclude_via_attr"],
        annotation = struct(
            copy_files = {"file_src": "file_dest"},
            copy_executables = {"exec_src": "exec_dest"},
            data = ["extra_target"],
            data_exclude_glob = ["data_exclude_all"],
            srcs_exclude_glob = ["srcs_exclude_all"],
            additive_build_content = """# SOMETHING SPECIAL AT THE END""",
        ),
        config_load = "@pypi//:config.bzl",
        group_name = "qux",
        purl = {"distribution": "foo", "file_name": "foo.whl", "version": "0"},
        group_deps = ["foo", "fox", "qux"],
    )
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

_tests.append(_test_all)

def _test_all_with_loads(env):
    want = """\
load("@pypi//:config.bzl", "packages")
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_targets")
load("@rules_python//python/private/pypi:whl_package_metadata.bzl", "whl_package_metadata")

package(default_visibility = ["//visibility:public"])

whl_library_targets(
    copy_executables = {
        "exec_src": "exec_dest",
    },
    copy_files = {
        "file_src": "file_dest",
    },
    data = ["extra_target"],
    data_exclude = [
        "exclude_via_attr",
        "data_exclude_all",
    ],
    dep_template = "@pypi//{name}:{target}",
    group_deps = [
        "foo",
        "fox",
        "qux",
    ],
    group_name = "qux",
    include = packages,
    metadata_name = "foo",
    name = "foo.whl",
    requires_dist = [
        "foo",
        "bar-baz",
        "qux",
    ],
    srcs_exclude = ["srcs_exclude_all"],
    tags = [
        "pypi_name=foo",
        "pypi_version=0",
    ],
)

whl_package_metadata(
    distribution = "foo",
    file_name = "foo.whl",
    version = "0",
)

# SOMETHING SPECIAL AT THE END
"""
    actual = generate_whl_library_build_bazel(
        metadata_version = "0",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        name = "foo.whl",
        requires_dist = ["foo", "bar-baz", "qux"],
        data_exclude = ["exclude_via_attr"],
        annotation = struct(
            copy_files = {"file_src": "file_dest"},
            copy_executables = {"exec_src": "exec_dest"},
            data = ["extra_target"],
            data_exclude_glob = ["data_exclude_all"],
            srcs_exclude_glob = ["srcs_exclude_all"],
            additive_build_content = """# SOMETHING SPECIAL AT THE END""",
        ),
        group_name = "qux",
        config_load = "@pypi//:config.bzl",
        group_deps = ["foo", "fox", "qux"],
        purl = {"distribution": "foo", "file_name": "foo.whl", "version": "0"},
    )
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

_tests.append(_test_all_with_loads)

def _test_deps_targets(env):
    want = """\
load("@rules_python//python/private/pypi:whl_library_deps_targets.bzl", "whl_library_deps_targets")

package(default_visibility = ["//visibility:public"])

whl_library_deps_targets(
    metadata_name = "foo",
    name = "foo.whl",
    repo = "@some_repo",
    tags = [
        "pypi_name=foo",
        "pypi_version=0",
    ],
)
"""
    actual = generate_whl_library_build_bazel(
        metadata_version = "0",
        metadata_name = "foo",
        name = "foo.whl",
        repo = "@some_repo",
        config_load = "",
    )
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

_tests.append(_test_deps_targets)

def _test_default_two_namespace_package_files(env):
    want = """\
load("@package_metadata//rules:package_metadata.bzl", "package_metadata")
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_targets")

package(default_visibility = ["//visibility:public"])

whl_library_targets(
    metadata_name = "foo",
    name = "foo.whl",
    namespace_package_files = ["site-packages/ns1/__init__.py", "site-packages/ns2/__init__.py"],
    tags = [
        "pypi_name=foo",
        "pypi_version=0",
    ],
)
"""
    actual = generate_whl_library_build_bazel(
        metadata_version = "0",
        metadata_name = "foo",
        name = "foo.whl",
        config_load = "@pypi//:config.bzl",
        namespace_package_files = [
            "site-packages/ns1/__init__.py",
            "site-packages/ns2/__init__.py",
        ],
    )
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

_tests.append(_test_default_two_namespace_package_files)

def _test_action_install(env):
    want = """\
load("@package_metadata//rules:package_metadata.bzl", "package_metadata")
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_targets")

package(default_visibility = ["//visibility:public"])

whl_library_targets(
    action_install = True,
    dep_template = "@pypi//{name}:{target}",
    extracted_files = [
        "bin/bar",
        "data/etc/d.txt",
        "include/foo.h",
        "site-packages/foo-0.dist-info/METADATA",
        "site-packages/foo/__init__.py",
    ],
    has_entry_points_txt = True,
    metadata_name = "foo",
    name = "foo.whl",
    namespace_package_files = ["site-packages/foo/__init__.py"],
    shebang_scripts = ["baz"],
    tags = [
        "pypi_name=foo",
        "pypi_version=0",
    ],
)
"""
    actual = generate_whl_library_build_bazel(
        metadata_version = "0",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        name = "foo.whl",
        config_load = "@pypi//:config.bzl",
        action_install = True,
        extracted_files = [
            "bin/bar",
            "data/etc/d.txt",
            "include/foo.h",
            "site-packages/foo-0.dist-info/METADATA",
            "site-packages/foo/__init__.py",
        ],
        has_entry_points_txt = True,
        namespace_package_files = ["site-packages/foo/__init__.py"],
        shebang_scripts = ["baz"],
    )
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

_tests.append(_test_action_install)

def _test_action_install_glob_warning(env):
    for action_install, content, want_warn in [
        (True, 'filegroup(name = "hdrs", srcs = glob(["site-packages/**/*.h"]))', True),
        (True, 'load("//bazel:pip_parse_targets.bzl", "define_targets")\ndefine_targets()', False),
        (False, 'filegroup(name = "hdrs", srcs = glob(["site-packages/**/*.h"]))', False),
        (
            True,
            '# never use glob(["*.h"]) here\nload("@rules_python//python:pip.bzl", "wheel_glob")\nfilegroup(name = "hdrs", srcs = wheel_glob(["site-packages/**/*.h"]))',
            False,
        ),
        (True, 'filegroup(name = "hdrs", srcs = glob (["site-packages/**/*.h"]))', True),
    ]:
        warnings = []
        generate_whl_library_build_bazel(
            metadata_version = "0",
            metadata_name = "foo",
            dep_template = "@pypi//{name}:{target}",
            name = "foo.whl",
            config_load = "@pypi//:config.bzl",
            action_install = action_install,
            extracted_files = ["site-packages/foo/__init__.py"] if action_install else [],
            annotation = struct(
                copy_files = {},
                copy_executables = {},
                data = [],
                data_exclude_glob = [],
                srcs_exclude_glob = [],
                additive_build_content = content,
            ),
            logger = struct(warn = warnings.append),
        )
        env.expect.that_int(len(warnings)).equals(1 if want_warn else 0)
        if want_warn:
            for substr in (
                "may glob wheel contents; globs match nothing under experimental_action_install",
                "wheel_glob()",
                "py_wheel_headers",
                "py_wheel_transform",
                "post_install_patches",
                "py_wheel_extract_files",
            ):
                env.expect.that_str(warnings[0]).contains(substr)

    # wheel_glob( in additive_build_content auto-loads wheel_glob and does not warn.
    wheel_glob_warnings = []
    wheel_glob_build = generate_whl_library_build_bazel(
        metadata_version = "0",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        name = "foo.whl",
        config_load = "@pypi//:config.bzl",
        action_install = True,
        extracted_files = ["site-packages/foo/libfoo.so"],
        annotation = struct(
            copy_files = {},
            copy_executables = {},
            data = [],
            data_exclude_glob = [],
            srcs_exclude_glob = [],
            additive_build_content = 'filegroup(name = "libs", srcs = wheel_glob(["site-packages/**/*.so"]))',
        ),
        logger = struct(warn = wheel_glob_warnings.append),
    )
    env.expect.that_int(len(wheel_glob_warnings)).equals(0)
    env.expect.that_str(wheel_glob_build).contains(
        'load("@rules_python//python/private/pypi:py_wheel_extract_files.bzl", "wheel_glob")',
    )

    wheel_files_bzl = generate_wheel_files_bzl([
        "site-packages/foo/__init__.py",
        "site-packages/foo/libfoo.so",
    ])
    env.expect.that_str(wheel_files_bzl).contains('"site-packages/foo/libfoo.so"')
    env.expect.that_str(wheel_files_bzl).contains("def wheel_glob(")
    env.expect.that_str(wheel_files_bzl).contains('wheel_library = Label("//:_wheel_install")')
    env.expect.that_str(wheel_files_bzl).contains("is_executable = False")

    # Classic mode also auto-loads wheel_glob when additive_build_content uses wheel_glob(.
    classic_wheel_glob_build = generate_whl_library_build_bazel(
        metadata_version = "0",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        name = "foo.whl",
        config_load = "@pypi//:config.bzl",
        annotation = struct(
            copy_files = {},
            copy_executables = {},
            data = [],
            data_exclude_glob = [],
            srcs_exclude_glob = [],
            additive_build_content = 'filegroup(name = "libs", srcs = wheel_glob(["site-packages/**/*.so"]))',
        ),
    )
    env.expect.that_str(classic_wheel_glob_build).contains(
        'load("@rules_python//python/private/pypi:py_wheel_extract_files.bzl", "wheel_glob")',
    )

_tests.append(_test_action_install_glob_warning)

def _test_action_sdist(env):
    pip_warnings = []
    parsed_cs = parse_sdist_extra_pip_args(
        [
            "--index-url",
            "https://pypi.org/simple",
            "-i",
            "https://mirror.example.com",
            "--extra-index-url=https://extra.example.com",
            "--trusted-host",
            "mirror.example.com",
            "--find-links=.",
            "-f",
            "wheels",
            "--no-index",
            "--isolated",
            "--cert=/etc/ssl/cert.pem",
            "--client-cert",
            "/etc/ssl/client.pem",
            "--proxy",
            "http://proxy:8080",
            "--retries=3",
            "--timeout",
            "30",
            "--cache-dir=/tmp/cache",
            "--no-cache-dir",
            "--prefer-binary",
            "--only-binary=:none:",
            "--no-binary",
            ":all:",
            "--pre",
            "--require-hashes",
            "--quiet",
            "-q",
            "--no-deps",
            "--use-pep517",
            "--platform=manylinux2014_x86_64",
            "-C",
            "cmake.define.FOO=from_pip_args",
            "-Ckeep_from_pip=1",
            "--config-settings",
            "setup-args=-Dbar=2",
            "--config-settings=build-dir=build",
            "-C--global-option=--quiet",
            "-C--global-option=--force",
            "-Cmalformed_no_equals",
            "--global-option=--cpp_implementation",
        ],
        logger = struct(warn = pip_warnings.append),
        name = "foo-1.0.tar.gz",
    )
    env.expect.that_dict(parsed_cs).contains_exactly({
        "--global-option": ["--quiet", "--force"],
        "build-dir": "build",
        "cmake.define.FOO": "from_pip_args",
        "keep_from_pip": "1",
        "setup-args": "-Dbar=2",
    })
    env.expect.that_int(len(pip_warnings)).equals(1)
    env.expect.that_str(pip_warnings[0]).contains("-Cmalformed_no_equals")
    env.expect.that_str(pip_warnings[0]).contains("--global-option=--cpp_implementation")
    env.expect.that_str(pip_warnings[0]).contains("ignored in experimental_action_install sdist builds")

    sdist_wheel_files_bzl = generate_sdist_wheel_files_bzl()
    env.expect.that_str(sdist_wheel_files_bzl).contains("FILES = []")
    env.expect.that_str(sdist_wheel_files_bzl).contains("cannot be used with an action-built sdist")

    want = """\
load("@package_metadata//rules:package_metadata.bzl", "package_metadata")
load("@pypi//:config.bzl", "packages")
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_targets")

package(default_visibility = ["//visibility:public"])

whl_library_targets(
    action_install = True,
    copy_executables = {},
    copy_files = {},
    data = [],
    data_exclude = [],
    dep_template = "@pypi//{name}:{target}",
    include = packages,
    metadata_name = "foo",
    name = "foo-1.0.sdist_build.whl",
    sdist = {
        "add_libdir_to_library_search_path": True,
        "build_requires": ["setuptools>=61", "wheel"],
        "config_settings": {"cmake.define.FOO": "from_whl_mods", "keep_from_pip": "1"},
        "config_settings_list": {"--global-option": ["--quiet", "--force"]},
        "environment": {"FOO_ENV": "1"},
        "pre_build_patch_strips": [1],
        "pre_build_patches": ["//patches:fix.patch"],
        "site_paths": ["foo"],
    },
    sdist_filename = "foo-1.0.tar.gz",
    srcs_exclude = [],
    tags = [
        "pypi_name=foo",
        "pypi_version=1.0",
    ],
)
"""
    actual = generate_whl_library_build_bazel(
        metadata_version = "1.0",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        name = "foo-1.0.sdist_build.whl",
        sdist_filename = "foo-1.0.tar.gz",
        config_load = "@pypi//:config.bzl",
        action_install = True,
        annotation = struct(
            copy_files = {},
            copy_executables = {},
            data = [],
            data_exclude_glob = [],
            sdist_config_settings = {"cmake.define.FOO": "from_whl_mods"},
            srcs_exclude_glob = [],
            additive_build_content = None,
        ),
        sdist = {
            "add_libdir_to_library_search_path": True,
            "build_requires": ["setuptools>=61", "wheel"],
            "config_settings": {
                "--global-option": ["--quiet", "--force"],
                "cmake.define.FOO": "from_pip_args",
                "keep_from_pip": "1",
            },
            "environment": {"FOO_ENV": "1"},
            "pre_build_patch_strips": [1],
            "pre_build_patches": ["//patches:fix.patch"],
            "site_paths": ["foo"],
        },
    )
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

_tests.append(_test_action_sdist)

def generate_whl_library_build_bazel_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
