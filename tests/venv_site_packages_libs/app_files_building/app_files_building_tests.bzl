""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:py_info.bzl", "VenvSymlinkEntry", "VenvSymlinkKind")  # buildifier: disable=bzl-visibility
load("//python/private:venv_runfiles.bzl", "build_link_map")  # buildifier: disable=bzl-visibility

_tests = []

def _ctx(workspace_name = "_main"):
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

def _test_overlapping_and_merging(env, _):
    entries = [
        _entry("a", "+pypi_a/site-packages/a", ["a.txt"]),
        _entry("a/b", "+pypi_a_b/site-packages/a/b", ["b.txt"]),
        _entry("x", "_main/src/x", ["x.txt"]),
        _entry("x/p", "_main/src-dev/x/p", ["p.txt"]),
        _entry("duplicate", "+dupe_a/site-packages/duplicate", ["d.py"]),
        # This entry also provides a/x.py, but since the "a" entry is shorter
        # and comes first, its version of x.py should win.
        _entry("duplicate", "+dupe_b/site-packages/duplicate", ["d.py"]),
    ]

    actual = build_link_map(_ctx(), entries)
    expected_libs = {
        "a/a.txt": _file("../+pypi_a/site-packages/a/a.txt"),
        "a/b/b.txt": _file("../+pypi_a_b/site-packages/a/b/b.txt"),
        "x/p/p.txt": _file("src-dev/x/p/p.txt"),
        "x/x.txt": _file("src/x/x.txt"),
        "duplicate/d.py": _file("../+dupe_a/site-packages/duplicate/d.py"),
    }
    env.expect.that_dict(actual[VenvSymlinkKind.LIB]).contains_exactly(expected_libs)
    env.expect.that_dict(actual).keys().contains_exactly([VenvSymlinkKind.LIB])

def _test_package_version_filtering(name):
    analysis_test(
        name = name,
        impl = _test_package_version_filtering_impl,
        target = "//python:none",
    )

_tests.append(_test_package_version_filtering)

def _test_package_version_filtering_impl(env, _):
    entries = [
        _entry("foo", "+pypi_foo_v1/site-packages/foo", ["foo.txt"], package = "foo", version = "1.0"),
        _entry("foo", "+pypi_foo_v2/site-packages/foo", ["bar.txt"], package = "foo", version = "2.0"),
    ]

    actual = build_link_map(_ctx(), entries)
    expected_libs = {
        "foo/foo.txt": _file("../+pypi_foo/site-packages/foo/foo.txt"),
    }
    env.expect.that_dict(actual[VenvSymlinkKind.LIB]).contains_exactly(expected_libs)

    actual = build_link_map(_ctx(), entries)
    expected_libs = {
        "a/x.py": _file("../+pypi_a/site-packages/a/x.py"),
    }
    env.expect.that_dict(actual[VenvSymlinkKind.LIB]).contains_exactly(expected_libs)

def _test_malformed_entry(name):
    analysis_test(
        name = name,
        impl = _test_malformed_entry_impl,
        target = "//python:none",
    )

_tests.append(_test_malformed_entry)

def _test_malformed_entry_impl(env, _):
    entries = [
        _entry(
            "a",
            "+pypi_a/site-packages/a",
            # This file is outside the link_to_path, so it should be ignored.
            ["../outside.txt"],
        ),
    ]

    actual = build_link_map(_ctx(), entries)
    env.expect.that_dict(actual).is_empty()

def _test_complex_namespace_packages(name):
    analysis_test(
        name = name,
        impl = _test_complex_namespace_packages_impl,
        target = "//python:none",
    )

_tests.append(_test_complex_namespace_packages)

def _test_complex_namespace_packages_impl(env, _):
    entries = [
        _entry("a/b", "+pypi_a_b/site-packages/a/b", ["b.txt"]),
        _entry("a/c", "+pypi_a_c/site-packages/a/c", ["c.txt"]),
        _entry("x/y/z", "+pypi_x_y_z/site-packages/x/y/z", ["z.txt"]),
        _entry("foo", "+pypi_foo/site-packages/foo", ["foo.txt"]),
        _entry("foobar", "+pypi_foobar/site-packages/foobar", ["foobar.txt"]),
    ]

    actual = build_link_map(_ctx(), entries)
    expected_libs = {
        "a/b/b.txt": _file("../+pypi_a_b/site-packages/a/b/b.txt"),
        "a/c/c.txt": _file("../+pypi_a_c/site-packages/a/c/c.txt"),
        "x/y/z/z.txt": _file("../+pypi_x_y_z/site-packages/x/y/z/z.txt"),
        "foo/foo.txt": _file("../+pypi_foo/site-packages/foo/foo.txt"),
        "foobar/foobar.txt": _file("../+pypi_foobar/site-packages/foobar/foobar.txt"),
    }
    env.expect.that_dict(actual[VenvSymlinkKind.LIB]).contains_exactly(expected_libs)

def _test_empty_and_trivial_inputs(name):
    analysis_test(
        name = name,
        impl = _test_empty_and_trivial_inputs_impl,
        target = "//python:none",
    )

_tests.append(_test_empty_and_trivial_inputs)

def _test_empty_and_trivial_inputs_impl(env, _):
    # Test with empty list of entries
    actual = build_link_map(_ctx(), [])
    env.expect.that_dict(actual).is_empty()

    # Test with an entry with no files
    entries = [_entry("a", "+pypi_a/site-packages/a", [])]
    actual = build_link_map(_ctx(), entries)
    env.expect.that_dict(actual).is_empty()

def _test_multiple_venv_symlink_kinds(name):
    analysis_test(
        name = name,
        impl = _test_multiple_venv_symlink_kinds_impl,
        target = "//python:none",
    )

_tests.append(_test_multiple_venv_symlink_kinds)

def _test_multiple_venv_symlink_kinds_impl(env, _):
    entries = [
        _entry("libfile", "+pypi_lib/site-packages/libfile", ["lib.txt"], kind = VenvSymlinkKind.LIB),
        _entry("binfile", "+pypi_bin/bin/binfile", ["bin.txt"], kind = VenvSymlinkKind.BIN),
        _entry("includefile", "+pypi_include/include/includefile", ["include.h"], kind = VenvSymlinkKind.INCLUDE),
    ]

    actual = build_link_map(_ctx(), entries)
    expected_libs = {
        "libfile/lib.txt": _file("../+pypi_lib/site-packages/libfile/lib.txt"),
    }
    expected_bins = {
        "binfile/bin.txt": _file("../+pypi_bin/bin/binfile/bin.txt"),
    }
    expected_includes = {
        "includefile/include.h": _file("../+pypi_include/include/includefile/include.h"),
    }
    env.expect.that_dict(actual[VenvSymlinkKind.LIB]).contains_exactly(expected_libs)
    env.expect.that_dict(actual[VenvSymlinkKind.BIN]).contains_exactly(expected_bins)
    env.expect.that_dict(actual[VenvSymlinkKind.INCLUDE]).contains_exactly(expected_includes)
    env.expect.that_dict(actual).keys().contains_exactly([
        VenvSymlinkKind.LIB,
        VenvSymlinkKind.BIN,
        VenvSymlinkKind.INCLUDE,
    ])

def app_files_building_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
