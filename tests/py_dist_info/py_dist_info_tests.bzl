"""Tests for py_dist_info."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_dist_info.bzl", "py_dist_info")

_tests = []

def _test_basic_dist_info(name):
    rt_util.helper_target(
        py_dist_info,
        name = name + "_subject",
        distribution = "my_pkg",
        version = "1.2.3",
    )
    analysis_test(
        name = name,
        impl = _test_basic_dist_info_impl,
        target = name + "_subject",
    )

def _test_basic_dist_info_impl(env, target):
    target_subject = env.expect.that_target(target)
    target_subject.default_outputs().contains_exactly([])
    target_subject.runfiles().contains_exactly([
        "{workspace}/my_pkg.dist-info/METADATA",
        "{workspace}/{package}/{name}_METADATA",
    ])

    metadata_action = target_subject.action_generating(
        "{package}/{name}_METADATA",
    )
    metadata_action.content().equals(
        "Metadata-Version: 2.1\nName: my_pkg\nVersion: 1.2.3\n",
    )

    wheel_metadata_action = target_subject.action_generating(
        "{package}/{name}.metadata.txt",
    )
    wheel_metadata_action.content().equals(
        "Metadata-Version: 2.1\nName: my_pkg\n",
    )

_tests.append(_test_basic_dist_info)

def _test_entry_points_and_target_path(name):
    rt_util.helper_target(
        py_dist_info,
        name = name + "_subject",
        console_scripts = {
            "legacy_cli": "my_pkg.cli:legacy",
        },
        distribution = "my_pkg",
        entry_points = {
            "console_scripts": [
                "my_cli = my_pkg.cli:main",
            ],
            "pytest11": [
                "my_plugin = my_pkg.plugin",
            ],
        },
        summary = "My package summary",
        target_path = "src/subpath",
        version = "2.0.0",
    )
    analysis_test(
        name = name,
        impl = _test_entry_points_and_target_path_impl,
        target = name + "_subject",
    )

def _test_entry_points_and_target_path_impl(env, target):
    target_subject = env.expect.that_target(target)
    target_subject.default_outputs().contains_exactly([])
    target_subject.runfiles().contains_exactly([
        "{workspace}/src/subpath/my_pkg.dist-info/METADATA",
        "{workspace}/src/subpath/my_pkg.dist-info/entry_points.txt",
        "{workspace}/{package}/{name}_METADATA",
        "{workspace}/{package}/{name}_entry_points.txt",
    ])

    metadata_action = target_subject.action_generating(
        "{package}/{name}_METADATA",
    )
    metadata_action.content().equals(
        "Metadata-Version: 2.1\nName: my_pkg\nVersion: 2.0.0\n" +
        "Summary: My package summary\n",
    )

    entry_points_action = target_subject.action_generating(
        "{package}/{name}_entry_points.txt",
    )
    entry_points_action.content().equals(
        "[console_scripts]\nlegacy_cli = my_pkg.cli:legacy\n" +
        "my_cli = my_pkg.cli:main\n\n" +
        "[pytest11]\nmy_plugin = my_pkg.plugin",
    )

_tests.append(_test_entry_points_and_target_path)

def py_dist_info_test_suite(name):
    """Creates the test suite for py_dist_info.

    Args:
        name: The name of the test suite.
    """
    test_suite(
        name = name,
        tests = _tests,
    )
