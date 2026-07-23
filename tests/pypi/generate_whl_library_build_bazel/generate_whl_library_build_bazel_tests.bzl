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
load("//python/private/pypi:generate_whl_library_build_bazel.bzl", "generate_whl_library_build_bazel", "generate_whl_library_deps_build_bazel")  # buildifier: disable=bzl-visibility

_tests = []

def _test_all_workspace(env):
    want = """\
load("@package_metadata//rules:package_metadata.bzl", "package_metadata")
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_srcs", "whl_library_from_requires_dist")
load("@pypi//:config.bzl", "packages")

package(default_visibility = ["//visibility:public"])

package_metadata(
    name = "package_metadata",
    purl = None,
    visibility = ["//:__subpackages__"],
)

whl_library_srcs(
    name = "foo.whl",
    data = [],
    sdist_filename = None,
    data_exclude = ["exclude_via_attr"],
    srcs_exclude = [],
    tags = [
        "pypi_name=foo",
        "pypi_version=1.0.0",
    ],
    entry_points = {},
    enable_implicit_namespace_pkgs = False,
    copy_files = {},
    copy_executables = {},
    namespace_package_files = {},
    visibility = ["//visibility:public"],
)

whl_library_from_requires_dist(
    name = "foo",
    version = "1.0.0",
    requires_dist = [
        "foo",
        "bar-baz",
        "qux",
    ],
    extras = [],
    group_deps = [
        "foo",
        "fox",
        "qux",
    ],
    dep_template = "@pypi//{name}:{target}",
    group_name = "qux",
    include = packages,
)
"""
    actual = generate_whl_library_build_bazel(
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
        metadata_name = "foo",
        metadata_version = "1.0.0",
    )

    # Strip the trailing newline and the additional_content from actual
    actual = actual.split("# SOMETHING SPECIAL AT THE END")[0].rstrip() + "\n"
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

_tests.append(_test_all_workspace)

def _test_all(env):
    want = """\
load("@package_metadata//rules:package_metadata.bzl", "package_metadata")
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_srcs", "whl_library_from_requires_dist")
load("@pypi//:config.bzl", "packages")

package(default_visibility = ["//visibility:public"])

package_metadata(
    name = "package_metadata",
    purl = None,
    visibility = ["//:__subpackages__"],
)

whl_library_srcs(
    name = "foo.whl",
    data = [],
    sdist_filename = None,
    data_exclude = ["exclude_via_attr"],
    srcs_exclude = [],
    tags = [
        "pypi_name=foo",
        "pypi_version=1.0.0",
    ],
    entry_points = {},
    enable_implicit_namespace_pkgs = False,
    copy_files = {},
    copy_executables = {},
    namespace_package_files = {},
    visibility = ["//visibility:public"],
)

whl_library_from_requires_dist(
    name = "foo",
    version = "1.0.0",
    requires_dist = [
        "foo",
        "bar-baz",
        "qux",
    ],
    extras = [],
    group_deps = [
        "foo",
        "fox",
        "qux",
    ],
    dep_template = "@pypi//{name}:{target}",
    group_name = "qux",
    include = packages,
)
"""
    actual = generate_whl_library_build_bazel(
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
        metadata_name = "foo",
        metadata_version = "1.0.0",
    )

    # Strip the trailing newline and the additional_content from actual
    actual = actual.split("# SOMETHING SPECIAL AT THE END")[0].rstrip() + "\n"
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

_tests.append(_test_all)

def _test_all_with_loads(env):
    want = """\
load("@package_metadata//rules:package_metadata.bzl", "package_metadata")
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_srcs", "whl_library_from_requires_dist")
load("@pypi//:config.bzl", "packages")

package(default_visibility = ["//visibility:public"])

package_metadata(
    name = "package_metadata",
    purl = None,
    visibility = ["//:__subpackages__"],
)

whl_library_srcs(
    name = "foo.whl",
    data = [],
    sdist_filename = None,
    data_exclude = ["exclude_via_attr"],
    srcs_exclude = [],
    tags = [
        "pypi_name=foo",
        "pypi_version=1.0.0",
    ],
    entry_points = {},
    enable_implicit_namespace_pkgs = False,
    copy_files = {},
    copy_executables = {},
    namespace_package_files = {},
    visibility = ["//visibility:public"],
)

whl_library_from_requires_dist(
    name = "foo",
    version = "1.0.0",
    requires_dist = [
        "foo",
        "bar-baz",
        "qux",
    ],
    extras = [],
    group_deps = [
        "foo",
        "fox",
        "qux",
    ],
    dep_template = "@pypi//{name}:{target}",
    group_name = "qux",
    include = packages,
)
"""
    actual = generate_whl_library_build_bazel(
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
        metadata_name = "foo",
        metadata_version = "1.0.0",
    )

    # Strip the trailing newline and the additional_content from actual
    actual = actual.split("# SOMETHING SPECIAL AT THE END")[0].rstrip() + "\n"
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

_tests.append(_test_all_with_loads)

def _test_generate_whl_library_deps_build_bazel(env):
    want = """\
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_from_requires_dist")

package(default_visibility = ["//visibility:public"])

whl_library_from_requires_dist(
    name = "foo",
    version = "1.0.0",
    requires_dist = [],
    extras = [],
    group_deps = [],
    dep_template = "template",
    group_name = None,
    src_pkg = "@//:pkg",
    aliases = [
        "data",
        "dist_info",
        "extracted_whl_files",
    ],
)
"""
    actual = generate_whl_library_deps_build_bazel(
        name = "foo",
        version = "1.0.0",
        config_load = None,
        dep_template = "template",
        entry_points = [],
        extras = [],
        group_deps = [],
        group_name = None,
        requires_dist = [],
        whl_library = "@@//:pkg",
    )
    env.expect.that_str(actual.replace("@@", "@")).equals(want)

def _test_no_annotation(env):
    want = """\
load("@package_metadata//rules:package_metadata.bzl", "package_metadata")
load("@rules_python//python/private/pypi:whl_library_targets.bzl", "whl_library_srcs", "whl_library_from_requires_dist")

package(default_visibility = ["//visibility:public"])

package_metadata(
    name = "package_metadata",
    purl = None,
    visibility = ["//:__subpackages__"],
)

whl_library_srcs(
    name = "foo.whl",
    data = [],
    sdist_filename = None,
    data_exclude = [],
    srcs_exclude = [],
    tags = [
        "pypi_name=foo",
        "pypi_version=1.0.0",
    ],
    entry_points = {},
    enable_implicit_namespace_pkgs = False,
    copy_files = {},
    copy_executables = {},
    namespace_package_files = {},
    visibility = ["//visibility:public"],
)

whl_library_from_requires_dist(
    name = "foo",
    version = "1.0.0",
    requires_dist = ["foo"],
    extras = [],
    group_deps = [],
    dep_template = "@pypi//{name}:{target}",
    group_name = None,
)
"""
    actual = generate_whl_library_build_bazel(
        dep_template = "@pypi//{name}:{target}",
        name = "foo.whl",
        requires_dist = ["foo"],
        annotation = None,
        config_load = None,
        metadata_name = "foo",
        metadata_version = "1.0.0",
    )
    env.expect.that_str(actual).equals(want)

_tests.append(_test_generate_whl_library_deps_build_bazel)
_tests.append(_test_no_annotation)

def generate_whl_library_build_bazel_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
