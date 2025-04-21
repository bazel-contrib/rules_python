# Copyright 2025 The Bazel Authors. All rights reserved.
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
"""Tests for construction of Python version matching config settings."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:pep508_deps.bzl", "deps")  # buildifier: disable=bzl-visibility

_tests = []

def test_simple_deps(env):
    got = deps(
        "foo",
        requires_dist = ["bar-Bar"],
    )
    env.expect.that_collection(got.deps).contains_exactly(["bar_bar"])
    env.expect.that_dict(got.deps_select).contains_exactly({})

_tests.append(test_simple_deps)

def test_can_add_os_specific_deps(env):
    for target in [
        struct(
            platforms = [
                "linux_x86_64",
                "osx_x86_64",
                "osx_aarch64",
                "windows_x86_64",
            ],
            python_version = "3.3.1",
        ),
        struct(
            platforms = [
                "cp33_linux_x86_64",
                "cp33_osx_x86_64",
                "cp33_osx_aarch64",
                "cp33_windows_x86_64",
            ],
            python_version = "",
        ),
    ]:
        got = deps(
            "foo",
            requires_dist = [
                "bar",
                "an_osx_dep; sys_platform=='darwin'",
                "posix_dep; os_name=='posix'",
                "win_dep; os_name=='nt'",
            ],
            platforms = target.platforms,
            default_python_version = target.python_version,
        )

        env.expect.that_collection(got.deps).contains_exactly(["bar"])
        env.expect.that_dict(got.deps_select).contains_exactly({
            "linux_x86_64": ["posix_dep"],
            "osx_aarch64": ["an_osx_dep", "posix_dep"],
            "osx_x86_64": ["an_osx_dep", "posix_dep"],
            "windows_x86_64": ["win_dep"],
        })

_tests.append(test_can_add_os_specific_deps)

def test_deps_are_added_to_more_specialized_platforms(env):
    got = deps(
        "foo",
        requires_dist = [
            "m1_dep; sys_platform=='darwin' and platform_machine=='arm64'",
            "mac_dep; sys_platform=='darwin'",
        ],
        platforms = [
            "osx_x86_64",
            "osx_aarch64",
        ],
        default_python_version = "3.8.4",
    )

    env.expect.that_collection(got.deps).contains_exactly(["mac_dep"])
    env.expect.that_dict(got.deps_select).contains_exactly({
        "osx_aarch64": ["m1_dep"],
    })

_tests.append(test_deps_are_added_to_more_specialized_platforms)

def test_non_platform_markers_are_added_to_common_deps(env):
    got = deps(
        "foo",
        requires_dist = [
            "bar",
            "baz; implementation_name=='cpython'",
            "m1_dep; sys_platform=='darwin' and platform_machine=='arm64'",
        ],
        platforms = [
            "linux_x86_64",
            "osx_x86_64",
            "osx_aarch64",
            "windows_x86_64",
        ],
        default_python_version = "3.8.4",
    )

    env.expect.that_collection(got.deps).contains_exactly(["bar", "baz"])
    env.expect.that_dict(got.deps_select).contains_exactly({
        "osx_aarch64": ["m1_dep"],
    })

_tests.append(test_non_platform_markers_are_added_to_common_deps)

def test_self_is_ignored(env):
    got = deps(
        "foo",
        requires_dist = [
            "bar",
            "req_dep; extra == 'requests'",
            "foo[requests]; extra == 'ssl'",
            "ssl_lib; extra == 'ssl'",
        ],
        extras = ["ssl"],
    )

    env.expect.that_collection(got.deps).contains_exactly(["bar", "req_dep", "ssl_lib"])
    env.expect.that_dict(got.deps_select).contains_exactly({})

_tests.append(test_self_is_ignored)

def test_self_dependencies_can_come_in_any_order(env):
    got = deps(
        "foo",
        requires_dist = [
            "bar",
            "baz; extra == 'feat'",
            "foo[feat2]; extra == 'all'",
            "foo[feat]; extra == 'feat2'",
            "zdep; extra == 'all'",
        ],
        extras = ["all"],
    )

    env.expect.that_collection(got.deps).contains_exactly(["bar", "baz", "zdep"])
    env.expect.that_dict(got.deps_select).contains_exactly({})

_tests.append(test_self_dependencies_can_come_in_any_order)

def _test_can_get_deps_based_on_specific_python_version(env):
    requires_dist = [
        "bar",
        "baz; python_version < '3.8'",
        "posix_dep; os_name=='posix' and python_version >= '3.8'",
    ]

    py38 = deps(
        "foo",
        requires_dist = requires_dist,
        platforms = ["cp38_linux_x86_64"],
    )
    py37 = deps(
        "foo",
        requires_dist = requires_dist,
        platforms = ["cp37_linux_x86_64"],
    )

    # since there is a single target platform, the deps_select will be empty
    env.expect.that_collection(py37.deps).contains_exactly(["bar", "baz"])
    env.expect.that_dict(py37.deps_select).contains_exactly({})
    env.expect.that_collection(py38.deps).contains_exactly(["bar", "posix_dep"])
    env.expect.that_dict(py38.deps_select).contains_exactly({})

_tests.append(_test_can_get_deps_based_on_specific_python_version)

def _test_no_version_select_when_single_version(env):
    got = deps(
        "foo",
        requires_dist = [
            "bar",
            "baz; python_version >= '3.8'",
            "posix_dep; os_name=='posix'",
            "posix_dep_with_version; os_name=='posix' and python_version >= '3.8'",
            "arch_dep; platform_machine=='x86_64' and python_version >= '3.8'",
        ],
        platforms = [
            "cp38_linux_x86_64",
            "cp38_windows_x86_64",
        ],
        default_python_version = "",
    )

    env.expect.that_collection(got.deps).contains_exactly(["bar", "baz", "arch_dep"])
    env.expect.that_dict(got.deps_select).contains_exactly({
        "linux_x86_64": ["posix_dep", "posix_dep_with_version"],
    })

_tests.append(_test_no_version_select_when_single_version)

def _test_can_get_version_select(env):
    requires_dist = [
        "bar",
        "baz; python_version < '3.8'",
        "baz_new; python_version >= '3.8'",
        "posix_dep; os_name=='posix'",
        "posix_dep_with_version; os_name=='posix' and python_version >= '3.8'",
        "arch_dep; platform_machine=='x86_64' and python_version < '3.8'",
    ]
    default_python_version = "3.7.4"

    got = deps(
        "foo",
        requires_dist = requires_dist,
        platforms = [
            "cp3{}_{}_x86_64".format(minor, os)
            for minor in [7, 8, 9]
            for os in ["linux", "windows"]
        ],
        default_python_version = default_python_version,
    )

    env.expect.that_collection(got.deps).contains_exactly(["bar"])
    env.expect.that_dict(got.deps_select).contains_exactly({
        "cp37_linux_x86_64": ["arch_dep", "baz", "posix_dep"],
        "cp37_windows_x86_64": ["arch_dep", "baz"],
        "cp38_linux_x86_64": ["baz_new", "posix_dep", "posix_dep_with_version"],
        "cp38_windows_x86_64": ["baz_new"],
        "cp39_linux_x86_64": ["baz_new", "posix_dep", "posix_dep_with_version"],
        "cp39_windows_x86_64": ["baz_new"],
        "linux_x86_64": ["arch_dep", "baz", "posix_dep"],
        "windows_x86_64": ["arch_dep", "baz"],
    })

_tests.append(_test_can_get_version_select)

def _test_deps_spanning_all_target_py_versions_are_added_to_common(env):
    requires_dist = [
        "bar",
        "baz (<2,>=1.11) ; python_version < '3.8'",
        "baz (<2,>=1.14) ; python_version >= '3.8'",
    ]
    default_python_version = "3.8.4"

    got = deps(
        "foo",
        requires_dist = requires_dist,
        platforms = [
            "cp3{}_linux_x86_64".format(minor)
            for minor in [7, 8, 9]
        ],
        default_python_version = default_python_version,
    )

    env.expect.that_collection(got.deps).contains_exactly(["bar", "baz"])
    env.expect.that_dict(got.deps_select).contains_exactly({})

_tests.append(_test_deps_spanning_all_target_py_versions_are_added_to_common)

def _test_deps_are_not_duplicated(env):
    default_python_version = "3.7.4"

    # See an example in
    # https://files.pythonhosted.org/packages/76/9e/db1c2d56c04b97981c06663384f45f28950a73d9acf840c4006d60d0a1ff/opencv_python-4.9.0.80-cp37-abi3-win32.whl.metadata
    requires_dist = [
        "bar >=0.1.0 ; python_version < '3.7'",
        "bar >=0.2.0 ; python_version >= '3.7'",
        "bar >=0.4.0 ; python_version >= '3.6' and platform_system == 'Linux' and platform_machine == 'aarch64'",
        "bar >=0.4.0 ; python_version >= '3.9'",
        "bar >=0.5.0 ; python_version <= '3.9' and platform_system == 'Darwin' and platform_machine == 'arm64'",
        "bar >=0.5.0 ; python_version >= '3.10' and platform_system == 'Darwin'",
        "bar >=0.5.0 ; python_version >= '3.10'",
        "bar >=0.6.0 ; python_version >= '3.11'",
    ]

    got = deps(
        "foo",
        requires_dist = requires_dist,
        platforms = [
            "cp3{}_{}_{}".format(minor, os, arch)
            for minor in [7, 10]
            for os in ["linux", "osx", "windows"]
            for arch in ["x86_64", "aarch64"]
        ],
        default_python_version = default_python_version,
    )

    env.expect.that_collection(got.deps).contains_exactly(["bar"])
    env.expect.that_dict(got.deps_select).contains_exactly({})

_tests.append(_test_deps_are_not_duplicated)

def _test_deps_are_not_duplicated_when_encountering_platform_dep_first(env):
    default_python_version = "3.7.1"

    # Note, that we are sorting the incoming `requires_dist` and we need to ensure that we are not getting any
    # issues even if the platform-specific line comes first.
    requires_dist = [
        "bar >=0.4.0 ; python_version >= '3.6' and platform_system == 'Linux' and platform_machine == 'aarch64'",
        "bar >=0.5.0 ; python_version >= '3.9'",
    ]

    got = deps(
        "foo",
        requires_dist = requires_dist,
        platforms = [
            "cp37_linux_aarch64",
            "cp37_linux_x86_64",
            "cp310_linux_aarch64",
            "cp310_linux_x86_64",
        ],
        default_python_version = default_python_version,
    )

    env.expect.that_collection(got.deps).contains_exactly([])
    env.expect.that_dict(got.deps_select).contains_exactly({
        "cp310_linux_aarch64": ["bar"],
        "cp310_linux_x86_64": ["bar"],
        "cp37_linux_aarch64": ["bar"],
        "linux_aarch64": ["bar"],
    })

_tests.append(_test_deps_are_not_duplicated_when_encountering_platform_dep_first)

def deps_test_suite(name):  # buildifier: disable=function-docstring
    test_suite(
        name = name,
        basic_tests = _tests,
    )
