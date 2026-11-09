"""Tests for the features of the Bazel versions."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python:features.bzl", "bazel_features")

_tests = []

def _test_bazel_features(env):
    for bazel_version, (supports_whl_extraction, extract_needs_chmod) in {
        # A development build is treated as the latest version.
        "": (True, False),
        "7.4.1": (False, True),
        "8.2.1": (False, True),
        "8.3.0": (True, True),
        "8.5.1": (True, True),
        "8.6.0": (True, False),
        "9.1.1": (True, False),
    }.items():
        got = bazel_features(bazel_version)
        env.expect.where(bazel_version = bazel_version).that_bool(
            got.supports_whl_extraction,
        ).equals(supports_whl_extraction)
        env.expect.where(bazel_version = bazel_version).that_bool(
            got.extract_needs_chmod,
        ).equals(extract_needs_chmod)

_tests.append(_test_bazel_features)

def bazel_features_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
