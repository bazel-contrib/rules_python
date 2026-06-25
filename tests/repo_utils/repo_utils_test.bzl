"""Unit tests for repo_utils.bzl."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:repo_utils.bzl", "repo_utils")  # buildifier: disable=bzl-visibility
load("//tests/support:mocks.bzl", "mocks")

_tests = []

def _make_rctx(*, os_name, mock_extracts = None, mock_files = None):
    mock_extracts = mock_extracts or {}
    mock_files = mock_files or {}
    execute_calls = []

    def _execute(arguments, **kwargs):
        _ = kwargs  # buildifier: disable=unused-variable
        execute_calls.append(arguments)
        return struct(return_code = 0, stdout = "", stderr = "")

    def _extract(archive, output = "", **kwargs):
        _ = kwargs  # buildifier: disable=unused-variable
        archive_str = str(archive)
        if archive_str in mock_extracts:
            for f, c in mock_extracts[archive_str].items():
                out_path = "{}/{}".format(output, f) if output else str(f)
                mock_files[out_path] = c

    def _path(x):
        return struct(
            exists = str(x) in mock_files,
            basename = str(x).split("/")[-1],
            dirname = "/".join(str(x).split("/")[:-1]),
        )

    rctx = struct(
        execute = _execute,
        extract = _extract,
        getenv = lambda key: "",
        path = _path,
        report_progress = lambda msg: None,
        os = struct(name = os_name),
        delete = lambda x: True,
        symlink = lambda target, link_name: None,
        name = "test_repo",
        attr = struct(
            _rule_name = "test_rule",
        ),
        _execute_calls = execute_calls,
    )
    return rctx

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

def _test_extract_calls_chmod_when_enabled(env):
    mock_rctx = _make_rctx(
        os_name = "linux",
        mock_extracts = {"test.whl": {"f1": "c1"}},
    )

    repo_utils.extract(
        mock_rctx,
        archive = mock_rctx.path("test.whl"),
        output = "out",
        supports_whl_extraction = True,
        extract_needs_chmod = True,
    )

    env.expect.that_bool(len(mock_rctx._execute_calls) > 0).equals(True)
    env.expect.that_str(mock_rctx._execute_calls[0][0]).equals("chmod")

_tests.append(_test_extract_calls_chmod_when_enabled)

def _test_extract_skips_chmod_when_disabled(env):
    mock_rctx = _make_rctx(
        os_name = "linux",
        mock_extracts = {"test.whl": {"f1": "c1"}},
    )

    repo_utils.extract(
        mock_rctx,
        archive = mock_rctx.path("test.whl"),
        output = "out",
        supports_whl_extraction = True,
        extract_needs_chmod = False,
    )

    env.expect.that_collection(mock_rctx._execute_calls).contains_exactly([])

_tests.append(_test_extract_skips_chmod_when_disabled)

def _test_maybe_fix_permissions_calls_chmod_on_linux(env):
    mock_rctx = _make_rctx(os_name = "linux")

    repo_utils.maybe_fix_permissions(
        mock_rctx,
        whl_path = mock_rctx.path("test.whl"),
    )

    env.expect.that_bool(len(mock_rctx._execute_calls) > 0).equals(True)
    env.expect.that_str(mock_rctx._execute_calls[0][0]).equals("chmod")

_tests.append(_test_maybe_fix_permissions_calls_chmod_on_linux)

def _test_maybe_fix_permissions_skips_on_windows(env):
    mock_rctx = _make_rctx(os_name = "windows")

    repo_utils.maybe_fix_permissions(
        mock_rctx,
        whl_path = mock_rctx.path("test.whl"),
    )

    env.expect.that_collection(mock_rctx._execute_calls).contains_exactly([])

_tests.append(_test_maybe_fix_permissions_skips_on_windows)

def repo_utils_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
