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

    # Relative URLs
    env.expect.that_str(urllib.absolute_url("https://example.com/relative", "file.whl")).equals("https://example.com/relative/file.whl")
    env.expect.that_str(urllib.absolute_url("https://example.com/relative/", "file.whl")).equals("https://example.com/relative/file.whl")
    env.expect.that_str(urllib.absolute_url("https://example.com/relative/", "../relative/file.whl")).equals("https://example.com/relative/file.whl")

    # Relative URL for files
    env.expect.that_str(urllib.absolute_url("file://{PYPI_BAZEL_WORKSPACE_ROOT}", "vendor/distro/file.whl")).equals("file://{PYPI_BAZEL_WORKSPACE_ROOT}/vendor/distro/file.whl")

_tests.append(_test_absolute_url)

def _test_strip_empty_path_segments(env):
    env.expect.that_str(urllib.strip_empty_path_segments("no/scheme//is/unchanged")).equals("no/scheme//is/unchanged")
    env.expect.that_str(urllib.strip_empty_path_segments("scheme://with/no/empty/segments")).equals("scheme://with/no/empty/segments")
    env.expect.that_str(urllib.strip_empty_path_segments("scheme://with//empty/segments")).equals("scheme://with/empty/segments")
    env.expect.that_str(urllib.strip_empty_path_segments("scheme://with///multiple//empty/segments")).equals("scheme://with/multiple/empty/segments")
    env.expect.that_str(urllib.strip_empty_path_segments("scheme://with//trailing/slash/")).equals("scheme://with/trailing/slash/")
    env.expect.that_str(urllib.strip_empty_path_segments("scheme://with/trailing/slashes///")).equals("scheme://with/trailing/slashes/")

_tests.append(_test_strip_empty_path_segments)

def urllib_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
