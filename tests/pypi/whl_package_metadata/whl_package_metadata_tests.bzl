""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:whl_package_metadata.bzl", "whl_package_metadata")  # buildifier: disable=bzl-visibility

_tests = []

def _purl(env, target):
    return json.decode(env.expect.that_target(target).action_generating(
        "{package}/{name}.package-metadata.json",
    ).actual.content)["purl"]

def _test_purl(name):
    whl_package_metadata(
        name = name + "_subject",
        distribution = "foo-bar",
        version = "1.0.0",
    )
    analysis_test(
        name = name,
        impl = _test_purl_impl,
        target = name + "_subject",
    )

def _test_purl_impl(env, target):
    env.expect.that_str(_purl(env, target)).equals("pkg:pypi/foo-bar@1.0.0")

_tests.append(_test_purl)

def _test_purl_with_qualifiers(name):
    whl_package_metadata(
        name = name + "_subject",
        distribution = "foo-bar",
        version = "1.0.0+local",
        repository_url = "https://example.org/simple",
        file_name = "foo_bar-1.0.0+local-py3-none-any.whl",
    )
    analysis_test(
        name = name,
        impl = _test_purl_with_qualifiers_impl,
        target = name + "_subject",
    )

def _test_purl_with_qualifiers_impl(env, target):
    # The qualifiers are sorted and the values are percent-encoded.
    env.expect.that_str(_purl(env, target)).equals(
        "pkg:pypi/foo-bar@1.0.0%2Blocal?file_name=foo_bar-1.0.0%2Blocal-py3-none-any.whl&repository_url=https:%2F%2Fexample.org%2Fsimple",
    )

_tests.append(_test_purl_with_qualifiers)

def whl_package_metadata_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, tests = _tests)
