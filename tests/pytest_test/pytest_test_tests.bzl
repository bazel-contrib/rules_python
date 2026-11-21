"""Tests for pytest_test."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo", rt_util = "util")
load("//python:py_library.bzl", "py_library")
load("//python:pytest_test.bzl", "pytest_test")
load(
    "//python/private/pytest_test:pytest_test.bzl",
    "get_version_test_name",
)  # buildifier: disable=bzl-visibility

_tests = []
_basic_tests = []

def _define_stub_deps(name):
    stub_names = (
        "pytest",
        "pytest_bazel",
        "pytest_shard",
        "pytest_randomly",
        "user_dep",
    )
    for suffix in stub_names:
        rt_util.helper_target(
            py_library,
            name = name + "_" + suffix,
        )

def _test_default_deps(name):
    _define_stub_deps(name)
    rt_util.helper_target(
        pytest_test,
        name = name + "_subject",
        srcs = ["basic_test.py"],
        pytest = ":" + name + "_pytest",
        pytest_bazel = ":" + name + "_pytest_bazel",
        # Verify pytest_shard is ignored when shard_count is unset.
        pytest_shard = ":" + name + "_pytest_shard",
    )
    analysis_test(
        name = name,
        impl = _test_default_deps_impl,
        target = name + "_subject",
    )

def _test_default_deps_impl(env, target):
    prefix = target.label.name[:-len("_subject")]
    env.expect.that_collection(target[TestingAspectInfo].attrs.deps).transform(
        desc = "target.label",
        map_each = lambda t: t.label,
    ).contains_exactly([
        Label(":" + prefix + "_pytest"),
        Label(":" + prefix + "_pytest_bazel"),
    ])

_tests.append(_test_default_deps)

def _test_optional_deps_with_select(name):
    _define_stub_deps(name)
    rt_util.helper_target(
        pytest_test,
        name = name + "_subject",
        srcs = ["basic_test.py"],
        pytest = ":" + name + "_pytest",
        pytest_bazel = ":" + name + "_pytest_bazel",
        pytest_shard = ":" + name + "_pytest_shard",
        pytest_randomly = ":" + name + "_pytest_randomly",
        shard_count = 2,
        deps = select({
            "//conditions:default": [":" + name + "_user_dep"],
        }),
    )
    analysis_test(
        name = name,
        impl = _test_optional_deps_with_select_impl,
        target = name + "_subject",
    )

def _test_optional_deps_with_select_impl(env, target):
    prefix = target.label.name[:-len("_subject")]
    env.expect.that_collection(target[TestingAspectInfo].attrs.deps).transform(
        desc = "target.label",
        map_each = lambda t: t.label,
    ).contains_exactly([
        Label(":" + prefix + "_user_dep"),
        Label(":" + prefix + "_pytest"),
        Label(":" + prefix + "_pytest_bazel"),
        Label(":" + prefix + "_pytest_shard"),
        Label(":" + prefix + "_pytest_randomly"),
    ])

_tests.append(_test_optional_deps_with_select)

def _test_get_version_test_name(env):
    want = {
        ("foo_test", "3.14"): "foo_py3.14_test",
        ("foo_test", "3.10"): "foo_py3.10_test",
        ("foo_test", "py3.14"): "foo_py3.14_test",
        ("foo_tests", "3.14"): "foo_py3.14_tests",
        ("foo", "3.14"): "foo_py3.14",
        ("test_foo", "3.14"): "test_foo_py3.14",
        ("basic_test", "3.11"): "basic_py3.11_test",
        ("pytest_default_test", "3.12"): "pytest_default_py3.12_test",
    }

    actual = {
        (name, ver): get_version_test_name(name, ver)
        for (name, ver) in want.keys()
    }
    env.expect.that_dict(actual).contains_exactly(want)

_basic_tests.append(_test_get_version_test_name)

def pytest_test_test_suite(name):
    """Create the test suite.

    Args:
        name: The name of the test suite.
    """
    test_suite(name = name, tests = _tests, basic_tests = _basic_tests)
