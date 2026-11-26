"""Analysis tests for py_sdist_wheel."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("//python/private/pypi:py_sdist_wheel.bzl", "py_sdist_wheel")  # buildifier: disable=bzl-visibility

_tests = []

def _test_unrecognized_target_cpu_fails(name):
    native.platform(
        name = name + "_ppc32_platform",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:ppc32",
        ],
    )
    py_sdist_wheel(
        name = name + "_subject",
        sdist = ":gen_demo_sdist",
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        config_settings = {
            "//command_line_option:platforms": str(native.package_relative_label(name + "_ppc32_platform")),
        },
        expect_failure = True,
        impl = _test_unrecognized_target_cpu_fails_impl,
        target = name + "_subject",
    )

def _test_unrecognized_target_cpu_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("recognized OS and CPU constraints"),
    )

_tests.append(_test_unrecognized_target_cpu_fails)

def py_sdist_wheel_bzl_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
