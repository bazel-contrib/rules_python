# Copyright 2025 The Bazel Authors. All rights reserved.
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

load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("@bazel_skylib//rules:native_binary.bzl", "native_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/uv:lock.bzl", "lock")
load("//python/uv/private:lock.bzl", lock_testing = "testing")  # buildifier: disable=bzl-visibility
load("//tests/support:py_reconfig.bzl", "py_reconfig_test")

_basic_tests = []

def _test_reroot(env):
    reroot = lock_testing.reroot
    env.expect.that_str(reroot("dev/requirements.in", "dev")).equals("requirements.in")
    env.expect.that_str(reroot("dev/sub/pkg.txt", "dev")).equals("sub/pkg.txt")
    env.expect.that_str(reroot("dev", "dev")).equals(".")
    env.expect.that_str(reroot("a/b/c/foo.txt", "a/b")).equals("c/foo.txt")
    env.expect.that_str(reroot("requirements.in", None)).equals("requirements.in")
    env.expect.that_str(reroot("requirements.in", "")).equals("requirements.in")

_basic_tests.append(_test_reroot)

def _test_reroot_all(env):
    reroot_all = lock_testing.reroot_all
    env.expect.that_collection(
        reroot_all(["dev/a.txt", "dev/b.txt"], "dev"),
    ).contains_exactly(["a.txt", "b.txt"]).in_order()

_basic_tests.append(_test_reroot_all)

def _test_up(env):
    up = lock_testing.up
    env.expect.that_str(up("foo/bar", None)).equals("foo/bar")
    env.expect.that_str(up("foo/bar", "")).equals("foo/bar")
    env.expect.that_str(up("foo/bar", "dev")).equals("../foo/bar")
    env.expect.that_str(up("foo/bar", "examples/bzlmod")).equals("../../foo/bar")
    env.expect.that_str(up("foo/bar", "a/b/c")).equals("../../../foo/bar")

_basic_tests.append(_test_up)

def lock_test_suite(name):
    """The test suite with various lock-related integration tests

    Args:
        name: {type}`str` the name of the test suite
    """
    lock(
        name = "requirements",
        srcs = ["testdata/requirements.in"],
        constraints = [
            "testdata/constraints.txt",
            "testdata/constraints2.txt",
        ],
        build_constraints = [
            "testdata/build_constraints.txt",
            "testdata/build_constraints2.txt",
        ],
        # It seems that the CI remote executors for the RBE do not have network
        # connectivity due to current CI setup.
        tags = ["no-remote-exec"],
        out = "testdata/requirements.txt",
    )

    lock(
        name = "requirements_directory",
        srcs = ["testdata/requirements.in"],
        constraints = [
            "testdata/constraints.txt",
            "testdata/constraints2.txt",
        ],
        build_constraints = [
            "testdata/build_constraints.txt",
            "testdata/build_constraints2.txt",
        ],
        directory = "tests/uv/lock/testdata",
        tags = ["no-remote-exec"],
        out = "testdata/requirements_directory.txt",
    )

    lock(
        name = "requirements_new_file",
        srcs = ["testdata/requirements.in"],
        out = "does_not_exist.txt",
        # It seems that the CI remote executors for the RBE do not have network
        # connectivity due to current CI setup.
        tags = ["no-remote-exec"],
    )

    py_reconfig_test(
        name = "requirements_run_tests",
        env = {
            "BUILD_WORKSPACE_DIRECTORY": "foo",
        },
        srcs = ["lock_run_test.py"],
        deps = [
            "//python/runfiles",
        ],
        data = [
            "requirements_new_file.update",
            "requirements_new_file.run",
            "requirements.update",
            "requirements.run",
            "requirements_directory.update",
            "requirements_directory.run",
            "testdata/requirements.txt",
            "testdata/requirements_directory.txt",
            "uv_lock_test.run",
            "uv_lock_directory_test.run",
            ":requirements",
            ":requirements_directory",
        ],
        main = "lock_run_test.py",
        tags = [
            "requires-network",
            # FIXME @aignas 2025-03-19: it seems that the RBE tests are failing
            # to execute the `requirements.run` targets that require network.
            #
            # We could potentially dump the required `.html` files and somehow
            # provide it to the `uv`, but may rely on internal uv handling of
            # `--index-url`.
            "no-remote-exec",
        ],
    )

    # Document and check that the action output matches the in-source file.
    diff_test(
        name = "requirements_test",
        timeout = "short",
        file1 = ":requirements",
        file2 = "testdata/requirements.txt",
    )

    diff_test(
        name = "requirements_directory_test",
        timeout = "short",
        file1 = ":requirements_directory",
        file2 = "testdata/requirements_directory.txt",
    )

    lock(
        name = "uv_lock_test",
        srcs = ["testdata/pyproject.toml"],
        out = "testdata/uv_lock_expected.lock",
        tags = ["no-remote-exec"],
    )

    lock(
        name = "uv_lock_directory_test",
        srcs = ["testdata/pyproject.toml"],
        directory = "tests/uv/lock/testdata",
        out = "testdata/uv_lock_expected.lock",
        tags = ["no-remote-exec"],
    )

    diff_test(
        name = "uv_lock_directory_diff_test",
        timeout = "short",
        file1 = ":uv_lock_directory_test",
        file2 = "testdata/uv_lock_expected.lock",
    )

    native_test(
        name = "uv_lock_test_check",
        src = ":uv_lock_test.update",
        target_compatible_with = select({
            "@platforms//os:windows": ["@platforms//:incompatible"],
            "//conditions:default": [],
        }),
    )

    test_suite(
        name = name + "_basic",
        basic_tests = _basic_tests,
    )

    native.test_suite(
        name = name,
        tests = [
            ":" + name + "_basic",
            ":requirements_test",
            ":requirements_directory_test",
            "//tests/uv/lock/pyproject_toml:requirements_test",
            ":requirements_run_tests",
            ":uv_lock_test_check",
            ":uv_lock_directory_diff_test",
        ],
    )
