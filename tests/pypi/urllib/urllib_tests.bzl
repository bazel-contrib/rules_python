""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:urllib.bzl", "urllib")  # buildifier: disable=bzl-visibility

_tests = []

def _test_absolute_url(env):
    # Already absolute
    for already_absolute in [
        "file://foo",
        "https://foo.com",
        "http://foo.com",
    ]:
        env.expect.that_str(urllib.absolute_url("https://ignored", already_absolute)).equals(already_absolute)

    # Simple with empty path segments
    env.expect.that_str(urllib.absolute_url("https://example.com//", "file.whl")).equals("https://example.com/file.whl")
    env.expect.that_str(urllib.absolute_url("https://example.com//a/b//", "../../file.whl")).equals("https://example.com/file.whl")
    env.expect.that_str(urllib.absolute_url("https://example.com//a/b//", "/file.whl")).equals("https://example.com/file.whl")

_tests.append(_test_absolute_url)

def urllib_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
