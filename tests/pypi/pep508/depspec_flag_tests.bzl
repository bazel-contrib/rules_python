load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//python/private/pypi:dependency_specifier_flag.bzl", "depspec_flag")
load("//python/private/pypi:pep508_env.bzl", pep508_env = "env")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:pep508_evaluate.bzl", "evaluate", "tokenize")  # buildifier: disable=bzl-visibility
load("//tests/support:support.bzl", "PYTHON_VERSION")

_tests = []

def _test_expr(name):
    def impl(env, target):
        attrs = target[TestingAspectInfo].attrs

        # todo: create FeatureFlagInfo subject
        actual = target[config_common.FeatureFlagInfo].value
        env.expect.where(
            expression = attrs.expression,
        ).that_str(actual).equals("yes")

    cases = {
        "python_version_gte": {
            "expression": "python_version >= '3.12.0'",
            "config_settings": {
                PYTHON_VERSION: "3.12.0",
            },
        },
    }

    tests = []
    for case_name, case in cases.items():
        test_name = name + "_" + case_name
        tests.append(test_name)
        depspec_flag(
            name = test_name + "_subject",
            expression = case["expression"],
        )
        analysis_test(
            name = test_name,
            impl = impl,
            target = test_name + "_subject",
            config_settings = case["config_settings"],
        )
    native.test_suite(
        name = name,
        tests = tests,
    )

_tests.append(_test_expr)

def depspec_flag_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
