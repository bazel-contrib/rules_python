load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:dependency_specifier_flag.bzl", "depspec_flag")
load("//python/private/pypi:pep508_env.bzl", pep508_env = "env")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:pep508_evaluate.bzl", "evaluate", "tokenize")  # buildifier: disable=bzl-visibility
load("//tests/support:support.bzl", "PYTHON_VERSION")

_tests = []

def _test_whatever(name):
    def impl(env, target):
        # todo: create FeatureFlagInfo subject
        actual = target[config_common.FeatureFlagInfo].value
        env.expect.that_string(actual).equals("yes")

    depspec_flag(
        name = name + "_subject",
        expression = "python_version >= '3.12.0'",
    )
    analysis_test(
        name = name,
        impl = impl,
        target = name + "_subject",
        config_settings = {
            PYTHON_VERSION: "3.12.0",
        },
    )

_tests.append(_test_whatever)

def depspec_flag_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
