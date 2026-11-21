"""Unit tests for python_repository.bzl."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:python_repository.bzl", "fix_up_dylib_id")  # buildifier: disable=bzl-visibility
load("//python/private:repo_utils.bzl", "repo_utils")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

_DYLIB = "libpython3.13.dylib"

def _logger(rctx, warnings):
    return repo_utils.logger(rctx, printer = lambda *a, **k: warnings.append(a))

def _test_rewrites_id_with_install_name_tool(env):
    rctx = mocks.rctx(
        os_name = "mac os x",
        mock_which = {"install_name_tool": "/usr/bin/install_name_tool"},
    )
    warnings = []

    fix_up_dylib_id(rctx, _DYLIB, logger = _logger(rctx, warnings))

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

    fix_up_dylib_id(rctx, _DYLIB, logger = _logger(rctx, warnings))

    env.expect.that_collection(rctx.execute_calls).contains_exactly([])
    env.expect.that_int(len(warnings)).equals(1)

_tests.append(_test_skips_without_install_name_tool)

def python_repository_test_suite(name):
    test_suite(name = name, basic_tests = _tests)
