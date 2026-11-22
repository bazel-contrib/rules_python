"""Unit tests for python_repository.bzl."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:python_repository.bzl", "fix_up_dylib_id", "release_from_urls")  # buildifier: disable=bzl-visibility
load("//python/private:repo_utils.bzl", "repo_utils")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

_DYLIB = "libpython3.13.dylib"

# The last release before python-build-standalone set the `@rpath` id itself.
_OLD_RELEASE = 20251205

def _logger(rctx, warnings):
    return repo_utils.logger(rctx, printer = lambda *a, **k: warnings.append(a))

def _test_rewrites_id_with_install_name_tool(env):
    rctx = mocks.rctx(
        os_name = "mac os x",
        mock_which = {"install_name_tool": "/usr/bin/install_name_tool"},
    )
    warnings = []

    fix_up_dylib_id(rctx, _DYLIB, release = _OLD_RELEASE, logger = _logger(rctx, warnings))

    env.expect.that_int(len(rctx.execute_calls)).equals(1)
    call = rctx.execute_calls[0]
    env.expect.that_str(call[0].basename).equals("install_name_tool")
    env.expect.that_collection(call[1:]).contains_exactly([
        "-id",
        "@rpath/" + _DYLIB,
        "lib/" + _DYLIB,
    ]).in_order()
    env.expect.that_collection(warnings).contains_exactly([])

_tests.append(_test_rewrites_id_with_install_name_tool)

def _test_skips_without_install_name_tool(env):
    rctx = mocks.rctx(
        os_name = "mac os x",
        environ = {"PATH": "/hermetic/bin"},
    )
    warnings = []

    fix_up_dylib_id(rctx, _DYLIB, release = _OLD_RELEASE, logger = _logger(rctx, warnings))

    env.expect.that_collection(rctx.execute_calls).contains_exactly([])
    env.expect.that_int(len(warnings)).equals(1)

_tests.append(_test_skips_without_install_name_tool)

def _test_rewrites_id_for_custom_url(env):
    rctx = mocks.rctx(
        os_name = "mac os x",
        mock_which = {"install_name_tool": "/usr/bin/install_name_tool"},
    )
    warnings = []

    fix_up_dylib_id(rctx, _DYLIB, release = None, logger = _logger(rctx, warnings))

    env.expect.that_int(len(rctx.execute_calls)).equals(1)

_tests.append(_test_rewrites_id_for_custom_url)

def _test_skips_for_release_with_rpath_id(env):
    rctx = mocks.rctx(
        os_name = "mac os x",
        mock_which = {"install_name_tool": "/usr/bin/install_name_tool"},
    )
    warnings = []

    fix_up_dylib_id(rctx, _DYLIB, release = 20251209, logger = _logger(rctx, warnings))

    env.expect.that_collection(rctx.execute_calls).contains_exactly([])
    env.expect.that_collection(warnings).contains_exactly([])

_tests.append(_test_skips_for_release_with_rpath_id)

def _test_release_from_urls(env):
    env.expect.that_int(release_from_urls([
        "https://github.com/astral-sh/python-build-standalone/releases/download/20251209/cpython-3.13.11+20251209-aarch64-apple-darwin-install_only.tar.gz",
        "https://mirror.example.com/cpython.tar.gz",
    ])).equals(20251209)
    env.expect.that_bool(release_from_urls([
        "https://mirror.example.com/python/cpython-3.13.tar.gz",
    ]) == None).equals(True)

_tests.append(_test_release_from_urls)

def python_repository_test_suite(name):
    test_suite(name = name, basic_tests = _tests)
