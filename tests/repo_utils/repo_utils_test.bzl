"""Unit tests for repo_utils.bzl."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:repo_utils.bzl", "repo_utils")  # buildifier: disable=bzl-visibility
load("//tests/support:mocks.bzl", "mocks")

_tests = []

def _test_get_platforms_os_name(env):
    mock_mrctx = mocks.rctx(os_name = "Mac OS X")
    got = repo_utils.get_platforms_os_name(mock_mrctx)
    env.expect.that_str(got).equals("osx")

_tests.append(_test_get_platforms_os_name)

def _test_relative_to(env):
    mock_mrctx_linux = mocks.rctx(os_name = "linux")
    mock_mrctx_win = mocks.rctx(os_name = "windows")

    # Case-sensitive matching (Linux)
    got = repo_utils.relative_to(mock_mrctx_linux, "foo/bar/baz", "foo/bar")
    env.expect.that_str(got).equals("baz")

    # Case-insensitive matching (Windows)
    got = repo_utils.relative_to(mock_mrctx_win, "C:/Foo/Bar/Baz", "c:/foo/bar")
    env.expect.that_str(got).equals("Baz")

    # Failure case
    failures = []

    def _mock_fail(msg):
        failures.append(msg)

    repo_utils.relative_to(mock_mrctx_linux, "foo/bar/baz", "qux", fail = _mock_fail)
    env.expect.that_collection(failures).contains_exactly(["foo/bar/baz is not relative to qux"])

_tests.append(_test_relative_to)

def _test_is_relative_to(env):
    mock_mrctx_linux = mocks.rctx(os_name = "linux")
    mock_mrctx_win = mocks.rctx(os_name = "windows")

    # Case-sensitive matching (Linux)
    env.expect.that_bool(repo_utils.is_relative_to(mock_mrctx_linux, "foo/bar/baz", "foo/bar")).equals(True)
    env.expect.that_bool(repo_utils.is_relative_to(mock_mrctx_linux, "foo/bar/baz", "qux")).equals(False)

    # Case-insensitive matching (Windows)
    env.expect.that_bool(repo_utils.is_relative_to(mock_mrctx_win, "C:/Foo/Bar/Baz", "c:/foo/bar")).equals(True)
    env.expect.that_bool(repo_utils.is_relative_to(mock_mrctx_win, "C:/Foo/Bar/Baz", "D:/Foo")).equals(False)

_tests.append(_test_is_relative_to)

def repo_utils_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
