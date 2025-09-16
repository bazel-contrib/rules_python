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

    def short_pathify(path):
        path = paths.join(link_to_path, path)

        # In tests, `../` is used to step out of the link_to_path scope.
        path = paths.normalize(path)

        # Treat paths starting with "+" as external references. This matches
        # how bzlmod names things.
        if link_to_path.startswith("+"):
            # File.short_path to external repos have `../` prefixed
            path = paths.join("../", path)
        else:
            # File.short_path in main repo is main-repo relative
            _, _, path = path.partition("/")
        return path

    return VenvSymlinkEntry(
        venv_path = venv_path,
        link_to_path = link_to_path,
        files = depset([
            _file(short_pathify(f))
            for f in files
        ]),
        **kwargs
    )

def _test_conflict_merging(name):
    analysis_test(
        name = name,
        impl = _test_conflict_merging_impl,
        target = "//python:none",
    )

_tests.append(_test_conflict_merging)

def _test_conflict_merging_impl(env, _):
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
        "duplicate/d.py": _file("../+dupe_a/site-packages/duplicate/d.py"),
        "x/p/p.txt": _file("src-dev/x/p/p.txt"),
        "x/x.txt": _file("src/x/x.txt"),
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
        _entry("foo", "+pypi_v1/site-packages/foo", ["foo.txt"], package = "foo", version = "1.0"),
        _entry("foo", "+pypi_v2/site-packages/foo", ["bar.txt"], package = "foo", version = "2.0"),
    ]

    actual = build_link_map(_ctx(), entries)

    expected_libs = {
        "foo": "+pypi_v1/site-packages/foo",
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
        # A second, conflicting, entry is added to force merging of the known
        # files. Without this, there's no conflict, so files is never
        # considered.
        _entry(
            "a",
            "+pypi_b/site-packages/a",
            ["../outside.txt"],
        ),
    ]

    actual = build_link_map(_ctx(), entries)
    env.expect.that_dict(actual).contains_exactly({
        VenvSymlinkKind.LIB: {},
    })

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
        "a/b": "+pypi_a_b/site-packages/a/b",
        "a/c": "+pypi_a_c/site-packages/a/c",
        "foo": "+pypi_foo/site-packages/foo",
        "foobar": "+pypi_foobar/site-packages/foobar",
        "x/y/z": "+pypi_x_y_z/site-packages/x/y/z",
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
    env.expect.that_dict(actual).contains_exactly({})

    # Test with an entry with no files
    entries = [_entry("a", "+pypi_a/site-packages/a", [])]
    actual = build_link_map(_ctx(), entries)
    env.expect.that_dict(actual).contains_exactly({
        VenvSymlinkKind.LIB: {"a": "+pypi_a/site-packages/a"},
    })

def _test_multiple_venv_symlink_kinds(name):
    analysis_test(
        name = name,
        impl = _test_multiple_venv_symlink_kinds_impl,
        target = "//python:none",
    )

_tests.append(_test_multiple_venv_symlink_kinds)

def _test_multiple_venv_symlink_kinds_impl(env, _):
    entries = [
        _entry(
            "libfile",
            "+pypi_lib/site-packages/libfile",
            ["lib.txt"],
            kind =
                VenvSymlinkKind.LIB,
        ),
        _entry(
            "binfile",
            "+pypi_bin/bin/binfile",
            ["bin.txt"],
            kind = VenvSymlinkKind.BIN,
        ),
        _entry(
            "includefile",
            "+pypi_include/include/includefile",
            ["include.h"],
            kind =
                VenvSymlinkKind.INCLUDE,
        ),
    ]

    actual = build_link_map(_ctx(), entries)

    expected_libs = {
        "libfile": "+pypi_lib/site-packages/libfile",
    }
    env.expect.that_dict(actual[VenvSymlinkKind.LIB]).contains_exactly(expected_libs)

    expected_bins = {
        "binfile": "+pypi_bin/bin/binfile",
    }
    env.expect.that_dict(actual[VenvSymlinkKind.BIN]).contains_exactly(expected_bins)

    expected_includes = {
        "includefile": "+pypi_include/include/includefile",
    }
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
