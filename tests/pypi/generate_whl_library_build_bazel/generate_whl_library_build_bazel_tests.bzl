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
load("//python/private/pypi:generate_whl_library_build_bazel.bzl", "generate_whl_library_build_bazel")  # buildifier: disable=bzl-visibility

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
        (True, '# never use glob(["*.h"]) here\npy_library(name = "extra")', False),
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
            env.expect.that_str(warnings[0]).contains(
                "may glob wheel contents; globs match nothing under experimental_action_install",
            )
            env.expect.that_str(warnings[0]).contains("':srcs' TreeArtifact")

_tests.append(_test_action_install_glob_warning)

def generate_whl_library_build_bazel_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
