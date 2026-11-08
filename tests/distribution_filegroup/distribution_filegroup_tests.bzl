"""Tests for distribution_filegroup helper."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load(
    "//python/private:distribution_filegroup.bzl",
    "distribution_filegroup",
)  # buildifier: disable=bzl-visibility

_tests = []

def _test_auto_subpackages_and_default_glob(name):
    distribution_filegroup(
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_auto_subpackages_and_default_glob_impl,
    )

def _test_auto_subpackages_and_default_glob_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([
        "{package}/f1.txt",
        "{package}/f2.txt",
        "{package}/subpkg/BUILD.bazel",
        "{package}/subpkg/subfile.txt",
    ])

_tests.append(_test_auto_subpackages_and_default_glob)

def _test_exclude_subpackage(name):
    distribution_filegroup(
        name = name + "_subject",
        exclude = ["subpkg"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_exclude_subpackage_impl,
    )

def _test_exclude_subpackage_impl(env, target):
    env.expect.that_target(target).default_outputs().contains_at_least([
        "{package}/f1.txt",
        "{package}/f2.txt",
    ])
    env.expect.that_target(target).default_outputs().not_contains(
        "{package}/subpkg/BUILD.bazel",
    )
    env.expect.that_target(target).default_outputs().not_contains(
        "{package}/subpkg/subfile.txt",
    )

_tests.append(_test_exclude_subpackage)

def distribution_filegroup_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
