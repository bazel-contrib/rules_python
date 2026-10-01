"""Tests for zip_stdlib rule."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load(
    "//python/private:zip_stdlib.bzl",
    "zip_stdlib",
)  # buildifier: disable=bzl-visibility

_tests = []

def _test_zip_stdlib_default(name):
    rt_util.helper_target(
        zip_stdlib,
        name = name + "_subject",
        out = "stdlib.zip",
        srcs = [":dummy_file.txt"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_zip_stdlib_default_impl,
    )

def _test_zip_stdlib_default_impl(env, target):
    action = env.expect.that_target(target).action_named("ZipStdlib")
    action.mnemonic().equals("ZipStdlib")
    action.contains_at_least_inputs(["tests/zip_stdlib/dummy_file.txt"])
    action.contains_at_least_args(["cC"])
    env.expect.that_target(target).default_outputs().contains_predicate(
        matching.file_basename_equals("stdlib.zip"),
    )

_tests.append(_test_zip_stdlib_default)

def _test_zip_stdlib_custom_out(name):
    rt_util.helper_target(
        zip_stdlib,
        name = name + "_subject",
        out = "lib/python311.zip",
        srcs = [":dummy_file.txt"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_zip_stdlib_custom_out_impl,
    )

def _test_zip_stdlib_custom_out_impl(env, target):
    action = env.expect.that_target(target).action_named("ZipStdlib")
    action.mnemonic().equals("ZipStdlib")
    env.expect.that_target(target).default_outputs().contains_predicate(
        matching.file_basename_equals("python311.zip"),
    )

_tests.append(_test_zip_stdlib_custom_out)

def _test_zip_stdlib_strip_prefix(name):
    rt_util.helper_target(
        zip_stdlib,
        name = name + "_subject",
        out = "stripped.zip",
        strip_prefix = "tests/zip_stdlib",
        srcs = [":dummy_file.txt"],
    )
    analysis_test(
        name = name,
        target = name + "_subject",
        impl = _test_zip_stdlib_strip_prefix_impl,
    )

def _test_zip_stdlib_strip_prefix_impl(env, target):
    action = env.expect.that_target(target).action_named("ZipStdlib")
    action.contains_at_least_inputs(["tests/zip_stdlib/dummy_file.txt"])

_tests.append(_test_zip_stdlib_strip_prefix)

def zip_stdlib_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
