load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:pep508_env.bzl", pep508_env = "env")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:pep508_evaluate.bzl", "evaluate", "tokenize")  # buildifier: disable=bzl-visibility

_tests = []

def test_whatever(name):
    def impl(env, target):
        # todo: create FeatureFlagInfo subject
        actual = target[config_common.FeatureFlagInfo].value
        env.expect.that_string(actual).equals("yes")

    depspec_flag(
        name = name + "_subject",
    )
    analysis_test(
        name = name,
        impl = impl,
        target = name + "_subject",
        config_settings = {
        },
    )

def depspec_flag_tests(name):
    test_suite(
        name = name,
        tests = _tests,
    )
