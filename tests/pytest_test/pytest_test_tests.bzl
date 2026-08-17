"""Tests for pytest_test."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load(
    "//tests/support/pytest_test:pytest_test.bzl",
    "get_version_test_name",
)

_tests = []

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

_tests.append(_test_get_version_test_name)

def pytest_test_test_suite(name):
    """Create the test suite.

    Args:
        name: The name of the test suite.
    """
    test_suite(name = name, basic_tests = _tests)
