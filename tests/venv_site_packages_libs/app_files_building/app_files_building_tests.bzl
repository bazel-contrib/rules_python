""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:py_info.bzl", "VenvSymlinkEntry", "VenvSymlinkKind")  # buildifier: disable=bzl-visibility
load("//python/private:venv_runfiles.bzl", "build_link_map")  # buildifier: disable=bzl-visibility

_tests = []

def _ctx(workspace_name):
    return struct(
        workspace_name = workspace_name,
    )

def _file(short_path):
    return struct(
        short_path = short_path,
    )

def _entry(venv_path, link_to_path, files = [], **kwargs):
    kwargs.setdefault("kind", VenvSymlinkKind.LIB)
    kwargs.setdefault("package", None)
    kwargs.setdefault("version", None)

    # Treat paths starting with "+" as external references. This matches
    # how bzlmod names things.
    if link_to_path.startswith("+"):
        # File.short_path to external repos have `../` prefixed
        short_path_prefix = "../{}".format(link_to_path)
    else:
        # File.short_path in main repo is main-repo relative
        _, _, short_path_prefix = link_to_path.partition("/")

    files = depset([
        _file(paths.join(short_path_prefix, f))
        for f in files
    ])
    return VenvSymlinkEntry(
        venv_path = venv_path,
        link_to_path = link_to_path,
        files = files,
        **kwargs
    )

def _test_build_link_map(name):
    analysis_test(
        name = name,
        impl = _test_build_link_map_impl,
        target = "//python:none",
    )

_tests.append(_test_build_link_map)

def _test_build_link_map_impl(env, _):
    entries = [
        _entry("a", "+pypi_a/site-packages/a", ["a.txt"]),
        _entry("a/b", "+pypi_a_b/site-packages/a/b", ["b.txt"]),
        _entry("x", "_main/src/x", ["x.txt"]),
        _entry("x/p", "_main/src-dev/x/p", ["p.txt"]),
    ]

    actual = build_link_map(_ctx("_main"), entries)
    expected_libs = {
        "a/a.txt": _file("../+pypi_a/site-packages/a/a.txt"),
        "a/b/b.txt": _file("../+pypi_a_b/site-packages/a/b/b.txt"),
        "x/p/p.txt": _file("src-dev/x/p/p.txt"),
        "x/x.txt": _file("src/x/x.txt"),
    }
    env.expect.that_dict(actual[VenvSymlinkKind.LIB]).contains_exactly(expected_libs)
    env.expect.that_dict(actual).keys().contains_exactly([VenvSymlinkKind.LIB])

def app_files_building_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
