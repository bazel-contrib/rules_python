""

load("@bazel_skylib//lib:types.bzl", "types")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_info.bzl", "PyInfo", "VenvSymlinkEntry", "VenvSymlinkKind")
load("//python:py_library.bzl", "py_library")
load("//python/private:common_labels.bzl", "labels")  # buildifier: disable=bzl-visibility
load("//python/private:py_info.bzl", "PyInfoBuilder")  # buildifier: disable=bzl-visibility
load("//python/private:venv_runfiles.bzl", "build_link_map", "get_venv_symlinks")  # buildifier: disable=bzl-visibility
load("//tests/support:support.bzl", "SUPPORTS_BZLMOD")

def _empty_files_impl(ctx):
    files = []
    for p in ctx.attr.paths:
        f = ctx.actions.declare_file(p)
        ctx.actions.write(output = f, content = "")
        files.append(f)
    return [DefaultInfo(files = depset(files))]

empty_files = rule(
    implementation = _empty_files_impl,
    attrs = {
        "paths": attr.string_list(
            doc = "A list of paths to create as files.",
            mandatory = True,
        ),
    },
)

_tests = []

# NOTE: In bzlmod, the workspace name is always "_main".
# Under workspace, the workspace name is the name configured in WORKSPACE,
# or "__main__" if was unspecified.
# NOTE: ctx.workspace_name is always the root workspace, not the workspace
# of the target being processed (ctx.label).
def _ctx(workspace_name = "_main"):
    return struct(
        workspace_name = workspace_name,
        label = Label("@@FAKE-CTX//:fake_ctx"),
    )

def _file(short_path, is_directory = False):
    return struct(
        short_path = short_path,
        is_directory = is_directory,
        owner = Label("//:fake_ctx"),
    )

def _venv_symlink(venv_path, *, link_to_path = None, files = []):
    return struct(
        link_to_path = link_to_path,
        venv_path = venv_path,
        files = files,
    )

def _venv_symlinks_from_entries(entries):
    result = []
    for symlink_entry in entries:
        result.append(struct(
            venv_path = symlink_entry.venv_path,
            link_to_path = symlink_entry.link_to_path,
            files = [f.short_path for f in symlink_entry.files.to_list()],
        ))
    return sorted(result, key = lambda e: (e.link_to_path, e.venv_path))

def _entry(venv_path, link_to_path, files, **kwargs):
    kwargs.setdefault("kind", VenvSymlinkKind.LIB)
    kwargs.setdefault("package", None)
    kwargs.setdefault("version", None)
    kwargs.setdefault("link_to_file", None)

    return VenvSymlinkEntry(
        venv_path = venv_path,
        link_to_path = link_to_path,
        files = depset(files),
        **kwargs
    )

def _assert_tree_artifact_equivalence(
        env,
        test_ctx,
        files,
        file_entries,
        package,
        version_str,
        namespace_package_files = []):
    pkg_prefix = env.ctx.label.package + "/"
    tree_artifact = _file(pkg_prefix + "srcs", is_directory = True)
    tree_files = [f.short_path[len(pkg_prefix):] for f in files]
    tree_ns_files = [f.short_path[len(pkg_prefix):] for f in namespace_package_files]
    tree_entries = get_venv_symlinks(
        test_ctx,
        tree_files,
        package = package,
        version_str = version_str,
        site_packages_root = "site-packages",
        namespace_package_files = tree_ns_files,
        tree_artifact = tree_artifact,
    )
    file_prefix = "{}/{}site-packages/".format(test_ctx.workspace_name, pkg_prefix)
    tree_prefix = "{}/{}srcs/site-packages/".format(test_ctx.workspace_name, pkg_prefix)
    file_summary = sorted([
        (
            e.kind,
            e.venv_path,
            e.package,
            e.version,
            e.link_to_path.replace(file_prefix, tree_prefix),
        )
        for e in file_entries
    ])
    tree_summary = sorted([
        (
            e.kind,
            e.venv_path,
            e.package,
            e.version,
            e.link_to_path,
        )
        for e in tree_entries
    ])
    env.expect.that_collection(tree_summary).contains_exactly(file_summary)

    other_entries = [
        _entry(
            e.venv_path,
            "+other/site-packages/" + e.venv_path,
            [_file("../+other/site-packages/" + e.venv_path + "/__other__.py")],
            kind = e.kind,
        )
        for e in file_entries
    ]
    file_merged = build_link_map(test_ctx, list(file_entries) + other_entries)
    tree_merged = build_link_map(test_ctx, list(tree_entries) + other_entries)
    for kind, kind_map in file_merged.items():
        expected_resolved = {}
        for k, v in kind_map.items():
            if types.is_string(v):
                expected_resolved[k] = v.replace(file_prefix, tree_prefix)
            else:
                expected_resolved[k] = "{}/{}".format(
                    test_ctx.workspace_name,
                    v.short_path,
                ).replace(file_prefix, tree_prefix)
        actual_resolved = {
            k: v if types.is_string(v) else "{}/{}".format(test_ctx.workspace_name, v.short_path)
            for k, v in tree_merged[kind].items()
        }
        env.expect.that_dict(actual_resolved).contains_exactly(expected_resolved)

def _test_conflict_merging(name):
    analysis_test(
        name = name,
        impl = _test_conflict_merging_impl,
        target = "//python:none",
    )

_tests.append(_test_conflict_merging)

def _test_conflict_merging_impl(env, _):
    entries = [
        _entry("a", "+pypi_a/site-packages/a", [
            _file("../+pypi_a/site-packages/a/a.txt"),
        ]),
        _entry("a-1.0.dist-info", "+pypi_a/site-packages/a-1.0.dist-info", [
            _file("../+pypi_a/site-packages/a-1.0.dist-info/METADATA"),
        ]),
        _entry("a/b", "+pypi_a_b/site-packages/a/b", [
            _file("../+pypi_a_b/site-packages/a/b/b.txt"),
        ]),
        _entry("x", "_main/src/x", [
            _file("src/x/x.txt"),
        ]),
        _entry("x/p", "_main/src-dev/x/p", [
            _file("src-dev/x/p/p.txt"),
        ]),
        _entry("duplicate", "+dupe_a/site-packages/duplicate", [
            _file("../+dupe_a/site-packages/duplicate/d.py"),
        ]),
        _entry("duplicate", "+dupe_b/site-packages/duplicate", [
            _file("../+dupe_b/site-packages/duplicate/d.py"),
        ]),
        # Case: two distributions provide the same file (instead of directory)
        _entry("ff/fmod.py", "+ff_a/site-packages/ff/fmod.py", [
            _file("../+ff_a/site-packages/ff/fmod.py"),
        ]),
        _entry("ff/fmod.py", "+ff_b/site-packages/ff/fmod.py", [
            _file("../+ff_b/site-packages/ff/fmod.py"),
        ]),
        # Case: two TreeArtifact distributions provide overlapping directories via link_to_subpaths
        _entry(
            "tree_a",
            "+tree_a/srcs/site-packages/tree_a",
            [_file("../+tree_a/srcs", is_directory = True)],
            link_to_subpaths = depset(["a.txt"]),
        ),
        _entry(
            "tree_a/b",
            "+tree_a_b/srcs/site-packages/tree_a/b",
            [_file("../+tree_a_b/srcs", is_directory = True)],
            link_to_subpaths = depset(["b.txt"]),
        ),
        # Case: two TreeArtifact distributions provide the same pkgutil __init__.py
        _entry("tree_ns/__init__.py", "+tree_a/srcs/site-packages/tree_ns/__init__.py", [
            _file("../+tree_a/srcs", is_directory = True),
        ]),
        _entry("tree_ns/__init__.py", "+tree_b/srcs/site-packages/tree_ns/__init__.py", [
            _file("../+tree_b/srcs", is_directory = True),
        ]),
    ]

    actual, conflicts = build_link_map(_ctx(), entries, return_conflicts = True)
    expected_libs = {
        "a-1.0.dist-info": "+pypi_a/site-packages/a-1.0.dist-info",
        "a/a.txt": _file("../+pypi_a/site-packages/a/a.txt"),
        "a/b/b.txt": _file("../+pypi_a_b/site-packages/a/b/b.txt"),
        "duplicate/d.py": _file("../+dupe_a/site-packages/duplicate/d.py"),
        "ff/fmod.py": _file("../+ff_a/site-packages/ff/fmod.py"),
        "tree_a/a.txt": "+tree_a/srcs/site-packages/tree_a/a.txt",
        "tree_a/b/b.txt": "+tree_a_b/srcs/site-packages/tree_a/b/b.txt",
        "tree_ns/__init__.py": "+tree_a/srcs/site-packages/tree_ns/__init__.py",
        "x/p/p.txt": _file("src-dev/x/p/p.txt"),
        "x/x.txt": _file("src/x/x.txt"),
    }
    env.expect.that_dict(actual[VenvSymlinkKind.LIB]).contains_exactly(expected_libs)
    env.expect.that_dict(actual).keys().contains_exactly([VenvSymlinkKind.LIB])

    env.expect.that_int(len(conflicts)).is_greater_than(0)

def _test_optimized_grouping_complex(name):
    empty_files(
        name = name + "_files",
        paths = [
            "site-packages/pkg1/a.txt",
            "site-packages/pkg1/b/b_mod_so",
            "site-packages/pkg1/c/c1.txt",
            "site-packages/pkg1/c/c2.txt",
            "site-packages/pkg1/d/d1.txt",
            "site-packages/pkg1/dd/dd1.txt",
            "site-packages/pkg1/q1/q1.txt",
            "site-packages/pkg1/q1/q2a/libq.so",
            "site-packages/pkg1/q1/q2a/q2.txt",
            "site-packages/pkg1/q1/q2a/q3/q3a.txt",
            "site-packages/pkg1/q1/q2a/q3/q3b.txt",
            "site-packages/pkg1/q1/q2b/q2b.txt",
            "site-packages/pkg1/q1/q2c/c_mod.so",
            "site-packages/pkg1/q1/q2c/q2.txt",
            "site-packages/pkg1/q1/q2c/q3/q3a.txt",
            "site-packages/pkg1/q1/q2c/q3/q3b.txt",
        ],
    )
    analysis_test(
        name = name,
        impl = _test_optimized_grouping_complex_impl,
        target = name + "_files",
    )

_tests.append(_test_optimized_grouping_complex)

def _test_optimized_grouping_complex_impl(env, target):
    test_ctx = _ctx(workspace_name = env.ctx.workspace_name)
    entries = get_venv_symlinks(
        test_ctx,
        target.files.to_list(),
        package = "pkg1",
        version_str = "1.0",
        site_packages_root = env.ctx.label.package + "/site-packages",
    )
    _assert_tree_artifact_equivalence(
        env,
        test_ctx,
        target.files.to_list(),
        entries,
        package = "pkg1",
        version_str = "1.0",
    )
    actual = _venv_symlinks_from_entries(entries)

    rr = "{}/{}/site-packages/".format(test_ctx.workspace_name, env.ctx.label.package)
    expected = [
        _venv_symlink(
            "pkg1/a.txt",
            link_to_path = rr + "pkg1/a.txt",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/a.txt",
            ],
        ),
        _venv_symlink(
            "pkg1/b",
            link_to_path = rr + "pkg1/b",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/b/b_mod_so",
            ],
        ),
        _venv_symlink("pkg1/c", link_to_path = rr + "pkg1/c", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/c/c1.txt",
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/c/c2.txt",
        ]),
        _venv_symlink("pkg1/d", link_to_path = rr + "pkg1/d", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/d/d1.txt",
        ]),
        _venv_symlink("pkg1/dd", link_to_path = rr + "pkg1/dd", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/dd/dd1.txt",
        ]),
        _venv_symlink("pkg1/q1/q1.txt", link_to_path = rr + "pkg1/q1/q1.txt", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/q1/q1.txt",
        ]),
        _venv_symlink("pkg1/q1/q2a/libq.so", link_to_path = rr + "pkg1/q1/q2a/libq.so", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/q1/q2a/libq.so",
        ]),
        _venv_symlink("pkg1/q1/q2a/q2.txt", link_to_path = rr + "pkg1/q1/q2a/q2.txt", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/q1/q2a/q2.txt",
        ]),
        _venv_symlink("pkg1/q1/q2a/q3", link_to_path = rr + "pkg1/q1/q2a/q3", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/q1/q2a/q3/q3a.txt",
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/q1/q2a/q3/q3b.txt",
        ]),
        _venv_symlink("pkg1/q1/q2b", link_to_path = rr + "pkg1/q1/q2b", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/q1/q2b/q2b.txt",
        ]),
        _venv_symlink("pkg1/q1/q2c/c_mod.so", link_to_path = rr + "pkg1/q1/q2c/c_mod.so", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/q1/q2c/c_mod.so",
        ]),
        _venv_symlink("pkg1/q1/q2c/q2.txt", link_to_path = rr + "pkg1/q1/q2c/q2.txt", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/q1/q2c/q2.txt",
        ]),
        _venv_symlink("pkg1/q1/q2c/q3", link_to_path = rr + "pkg1/q1/q2c/q3", files = [
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/q1/q2c/q3/q3a.txt",
            "tests/venv_site_packages_libs/app_files_building/site-packages/pkg1/q1/q2c/q3/q3b.txt",
        ]),
    ]
    expected = sorted(expected, key = lambda e: (e.link_to_path, e.venv_path))
    env.expect.that_collection(
        actual,
    ).contains_exactly(expected)
    _, conflicts = build_link_map(test_ctx, entries, return_conflicts = True)

    # The point of the optimization is to avoid having to merge conflicts.
    env.expect.that_collection(conflicts).contains_exactly([])

def _test_optimized_grouping_single_toplevel(name):
    empty_files(
        name = name + "_files",
        paths = [
            "site-packages/pkg2/__init__.py",
            "site-packages/pkg2/a.txt",
            "site-packages/pkg2/b_mod_so",
        ],
    )
    analysis_test(
        name = name,
        impl = _test_optimized_grouping_single_toplevel_impl,
        target = name + "_files",
    )

_tests.append(_test_optimized_grouping_single_toplevel)

def _test_optimized_grouping_single_toplevel_impl(env, target):
    test_ctx = _ctx(workspace_name = env.ctx.workspace_name)
    entries = get_venv_symlinks(
        test_ctx,
        target.files.to_list(),
        package = "pkg2",
        version_str = "1.0",
        site_packages_root = env.ctx.label.package + "/site-packages",
    )
    _assert_tree_artifact_equivalence(
        env,
        test_ctx,
        target.files.to_list(),
        entries,
        package = "pkg2",
        version_str = "1.0",
    )
    actual = _venv_symlinks_from_entries(entries)

    rr = "{}/{}/site-packages/".format(test_ctx.workspace_name, env.ctx.label.package)
    expected = [
        _venv_symlink(
            "pkg2",
            link_to_path = rr + "pkg2",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/pkg2/__init__.py",
                "tests/venv_site_packages_libs/app_files_building/site-packages/pkg2/a.txt",
                "tests/venv_site_packages_libs/app_files_building/site-packages/pkg2/b_mod_so",
            ],
        ),
    ]
    expected = sorted(expected, key = lambda e: (e.link_to_path, e.venv_path))

    env.expect.that_collection(
        actual,
    ).contains_exactly(expected)

    _, conflicts = build_link_map(test_ctx, entries, return_conflicts = True)

    # The point of the optimization is to avoid having to merge conflicts.
    env.expect.that_collection(conflicts).contains_exactly([])

def _test_optimized_grouping_implicit_namespace_packages(name):
    empty_files(
        name = name + "_files",
        paths = [
            # NOTE: An alphanumeric name with underscores is used to verify
            # name matching is correct.
            "site-packages/name_space9/part1/foo.py",
            "site-packages/name_space9/part2/bar.py",
            "site-packages/name_space9-1.0.dist-info/METADATA",
        ],
    )
    analysis_test(
        name = name,
        impl = _test_optimized_grouping_implicit_namespace_packages_impl,
        target = name + "_files",
    )

_tests.append(_test_optimized_grouping_implicit_namespace_packages)

def _test_optimized_grouping_implicit_namespace_packages_impl(env, target):
    test_ctx = _ctx(workspace_name = env.ctx.workspace_name)
    entries = get_venv_symlinks(
        test_ctx,
        target.files.to_list(),
        package = "pkg3",
        version_str = "1.0",
        site_packages_root = env.ctx.label.package + "/site-packages",
    )
    _assert_tree_artifact_equivalence(
        env,
        test_ctx,
        target.files.to_list(),
        entries,
        package = "pkg3",
        version_str = "1.0",
    )
    actual = _venv_symlinks_from_entries(entries)

    rr = "{}/{}/site-packages/".format(test_ctx.workspace_name, env.ctx.label.package)
    expected = [
        _venv_symlink(
            "name_space9/part1",
            link_to_path = rr + "name_space9/part1",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/name_space9/part1/foo.py",
            ],
        ),
        _venv_symlink(
            "name_space9/part2",
            link_to_path = rr + "name_space9/part2",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/name_space9/part2/bar.py",
            ],
        ),
        _venv_symlink(
            "name_space9-1.0.dist-info",
            link_to_path = rr + "name_space9-1.0.dist-info",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/name_space9-1.0.dist-info/METADATA",
            ],
        ),
    ]
    expected = sorted(expected, key = lambda e: (e.link_to_path, e.venv_path))
    env.expect.that_collection(
        actual,
    ).contains_exactly(expected)

    _, conflicts = build_link_map(test_ctx, entries, return_conflicts = True)

    # The point of the optimization is to avoid having to merge conflicts.
    env.expect.that_collection(conflicts).contains_exactly([])

def _test_optimized_grouping_pkgutil_namespace_packages(name):
    empty_files(
        name = name + "_files",
        paths = [
            "site-packages/pkgutilns/__init__.py",
            "site-packages/pkgutilns/foo.py",
            # Special cases: These dirnames under site-packages are always
            # treated as namespace packages
            "site-packages/nvidia/whatever/w.py",
        ],
    )
    analysis_test(
        name = name,
        impl = _test_optimized_grouping_pkgutil_namespace_packages_impl,
        target = name + "_files",
    )

_tests.append(_test_optimized_grouping_pkgutil_namespace_packages)

def _test_optimized_grouping_pkgutil_namespace_packages_impl(env, target):
    test_ctx = _ctx(workspace_name = env.ctx.workspace_name)
    files = target.files.to_list()
    ns_inits = [f for f in files if f.basename == "__init__.py"]

    entries = get_venv_symlinks(
        test_ctx,
        files,
        package = "pkgutilns",
        version_str = "1.0",
        site_packages_root = env.ctx.label.package + "/site-packages",
        namespace_package_files = ns_inits,
    )
    _assert_tree_artifact_equivalence(
        env,
        test_ctx,
        files,
        entries,
        package = "pkgutilns",
        version_str = "1.0",
        namespace_package_files = ns_inits,
    )
    actual = _venv_symlinks_from_entries(entries)

    rr = "{}/{}/site-packages/".format(test_ctx.workspace_name, env.ctx.label.package)
    expected = [
        _venv_symlink(
            "pkgutilns/__init__.py",
            link_to_path = rr + "pkgutilns/__init__.py",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/pkgutilns/__init__.py",
            ],
        ),
        _venv_symlink(
            "pkgutilns/foo.py",
            link_to_path = rr + "pkgutilns/foo.py",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/pkgutilns/foo.py",
            ],
        ),
        _venv_symlink(
            "nvidia/whatever",
            link_to_path = rr + "nvidia/whatever",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/nvidia/whatever/w.py",
            ],
        ),
    ]
    expected = sorted(expected, key = lambda e: (e.link_to_path, e.venv_path))
    env.expect.that_collection(
        actual,
    ).contains_exactly(expected)

    _, conflicts = build_link_map(test_ctx, entries, return_conflicts = True)

    # The point of the optimization is to avoid having to merge conflicts.
    env.expect.that_collection(conflicts).contains_exactly([])

def _test_optimized_grouping_pkgutil_whls(name):
    """Verify that the whl_library pkgutli style detection logic works."""
    py_library(
        name = name + "_lib",
        deps = [
            "@pkgutil_nspkg1//:pkg",
            "@pkgutil_nspkg2//:pkg",
        ],
        target_compatible_with = SUPPORTS_BZLMOD,
    )
    analysis_test(
        name = name,
        impl = _test_optimized_grouping_pkgutil_whls_impl,
        target = name + "_lib",
        config_settings = {
            labels.VENVS_SITE_PACKAGES: "yes",
        },
        attr_values = dict(
            target_compatible_with = SUPPORTS_BZLMOD,
        ),
    )

_tests.append(_test_optimized_grouping_pkgutil_whls)

def _test_optimized_grouping_pkgutil_whls_impl(env, target):
    test_ctx = _ctx(workspace_name = env.ctx.workspace_name)
    actual_raw_entries = target[PyInfo].venv_symlinks.to_list()

    actual = _venv_symlinks_from_entries(actual_raw_entries)

    # The important condition is that the top-level 'nspkg' directory
    # is NOT linked because it's a pkgutil namespace package.
    env.expect.that_collection(actual).contains_exactly([
        # Entries from pkgutil_ns1
        _venv_symlink(
            "nspkg/__init__.py",
            link_to_path = "+internal_dev_deps+pkgutil_nspkg1/site-packages/nspkg/__init__.py",
            files = [
                "../+internal_dev_deps+pkgutil_nspkg1/site-packages/nspkg/__init__.py",
            ],
        ),
        _venv_symlink(
            "nspkg/one",
            link_to_path = "+internal_dev_deps+pkgutil_nspkg1/site-packages/nspkg/one",
            files = [
                "../+internal_dev_deps+pkgutil_nspkg1/site-packages/nspkg/one/a.txt",
            ],
        ),
        _venv_symlink(
            "pkgutil_nspkg1-1.0.dist-info",
            link_to_path = "+internal_dev_deps+pkgutil_nspkg1/site-packages/pkgutil_nspkg1-1.0.dist-info",
            files = [
                "../+internal_dev_deps+pkgutil_nspkg1/site-packages/pkgutil_nspkg1-1.0.dist-info/INSTALLER",
                "../+internal_dev_deps+pkgutil_nspkg1/site-packages/pkgutil_nspkg1-1.0.dist-info/METADATA",
                "../+internal_dev_deps+pkgutil_nspkg1/site-packages/pkgutil_nspkg1-1.0.dist-info/RECORD",
                "../+internal_dev_deps+pkgutil_nspkg1/site-packages/pkgutil_nspkg1-1.0.dist-info/WHEEL",
            ],
        ),
        # Entries from pkgutil_ns2
        _venv_symlink(
            "nspkg/__init__.py",
            link_to_path = "+internal_dev_deps+pkgutil_nspkg2/site-packages/nspkg/__init__.py",
            files = [
                "../+internal_dev_deps+pkgutil_nspkg2/site-packages/nspkg/__init__.py",
            ],
        ),
        _venv_symlink(
            "nspkg/two",
            link_to_path = "+internal_dev_deps+pkgutil_nspkg2/site-packages/nspkg/two",
            files = [
                "../+internal_dev_deps+pkgutil_nspkg2/site-packages/nspkg/two/b.txt",
            ],
        ),
        _venv_symlink(
            "pkgutil_nspkg2-1.0.dist-info",
            link_to_path = "+internal_dev_deps+pkgutil_nspkg2/site-packages/pkgutil_nspkg2-1.0.dist-info",
            files = [
                "../+internal_dev_deps+pkgutil_nspkg2/site-packages/pkgutil_nspkg2-1.0.dist-info/INSTALLER",
                "../+internal_dev_deps+pkgutil_nspkg2/site-packages/pkgutil_nspkg2-1.0.dist-info/METADATA",
                "../+internal_dev_deps+pkgutil_nspkg2/site-packages/pkgutil_nspkg2-1.0.dist-info/RECORD",
                "../+internal_dev_deps+pkgutil_nspkg2/site-packages/pkgutil_nspkg2-1.0.dist-info/WHEEL",
            ],
        ),
    ])

    # Verifying that the expected VenvSymlink structure is processed with minimal number
    # of conflicts (Just the single pkgutil style __init__.py file)
    _, conflicts = build_link_map(test_ctx, actual_raw_entries, return_conflicts = True)
    env.expect.that_collection(_venv_symlinks_from_entries(conflicts[0])).contains_exactly([
        _venv_symlink(
            "nspkg/__init__.py",
            link_to_path = "+internal_dev_deps+pkgutil_nspkg1/site-packages/nspkg/__init__.py",
            files = [
                "../+internal_dev_deps+pkgutil_nspkg1/site-packages/nspkg/__init__.py",
            ],
        ),
        _venv_symlink(
            "nspkg/__init__.py",
            link_to_path = "+internal_dev_deps+pkgutil_nspkg2/site-packages/nspkg/__init__.py",
            files = [
                "../+internal_dev_deps+pkgutil_nspkg2/site-packages/nspkg/__init__.py",
            ],
        ),
    ])
    env.expect.that_collection(conflicts).has_size(1)

def _test_package_version_filtering(name):
    analysis_test(
        name = name,
        impl = _test_package_version_filtering_impl,
        target = "//python:none",
    )

_tests.append(_test_package_version_filtering)

def _test_package_version_filtering_impl(env, _):
    entries = [
        _entry("foo", "+pypi_v1/site-packages/foo", [
            _file("../+pypi_v1/site-packages/foo/foo.txt"),
        ], package = "foo", version = "1.0"),
        _entry("foo", "+pypi_v2/site-packages/foo", [
            _file("../+pypi_v2/site-packages/foo/bar.txt"),
        ], package = "foo", version = "2.0"),
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
            [_file("../+pypi_a/site-packages/outside.txt")],
        ),
        # A second, conflicting, entry is added to force merging of the known
        # files. Without this, there's no conflict, so files is never
        # considered.
        _entry(
            "a",
            "+pypi_b/site-packages/a",
            [_file("../+pypi_b/site-packages/outside.txt")],
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
        _entry("a/b", "+pypi_a_b/site-packages/a/b", [
            _file("../+pypi_a_b/site-packages/a/b/b.txt"),
        ]),
        _entry("a/c", "+pypi_a_c/site-packages/a/c", [
            _file("../+pypi_a_c/site-packages/a/cc.txt"),
        ]),
        _entry("x/y/z", "+pypi_x_y_z/site-packages/x/y/z", [
            _file("../+pypi_x_y_z/site-packages/x/y/z/z.txt"),
        ]),
        _entry("foo", "+pypi_foo/site-packages/foo", [
            _file("../+pypi_foo/site-packages/foo/foo.txt"),
        ]),
        _entry("foobar", "+pypi_foobar/site-packages/foobar", [
            _file("../+pypi_foobar/site-packages/foobar/foobar.txt"),
        ]),
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
            [_file("../+pypi_lib/site-packages/libfile/lib.txt")],
            kind = VenvSymlinkKind.LIB,
        ),
        _entry(
            "binfile",
            "+pypi_bin/bin/binfile",
            [_file("../+pypi_bin/bin/binfile/bin.txt")],
            kind = VenvSymlinkKind.BIN,
        ),
        _entry(
            "includefile",
            "+pypi_include/include/includefile",
            [_file("../+pypi_include/include/includefile/include.h")],
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

def _test_shared_library_symlinking(name):
    empty_files(
        name = name + "_files",
        # NOTE: Test relies upon order
        paths = [
            "site-packages/bar/libs/liby.so",
            "site-packages/bar/x.py",
            "site-packages/bar/y.so",
            "site-packages/foo.libs/libx.so",
            "site-packages/foo/a.py",
            "site-packages/foo/b.so",
            "site-packages/root.pth",
            "site-packages/root.py",
            "site-packages/root.so",
        ],
    )
    analysis_test(
        name = name,
        impl = _test_shared_library_symlinking_impl,
        target = name + "_files",
    )

_tests.append(_test_shared_library_symlinking)

def _test_shared_library_symlinking_impl(env, target):
    srcs = target.files.to_list()
    actual_entries = get_venv_symlinks(
        _ctx(),
        srcs,
        package = "foo",
        version_str = "1.0",
        site_packages_root = env.ctx.label.package + "/site-packages",
    )
    _assert_tree_artifact_equivalence(
        env,
        _ctx(),
        srcs,
        actual_entries,
        package = "foo",
        version_str = "1.0",
    )

    actual = _venv_symlinks_from_entries(actual_entries)

    env.expect.that_collection(actual).contains_at_least([
        _venv_symlink(
            "bar/libs/liby.so",
            link_to_path = "_main/tests/venv_site_packages_libs/app_files_building/site-packages/bar/libs/liby.so",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/bar/libs/liby.so",
            ],
        ),
        _venv_symlink(
            "foo.libs/libx.so",
            link_to_path = "_main/tests/venv_site_packages_libs/app_files_building/site-packages/foo.libs/libx.so",
            files = [
                "tests/venv_site_packages_libs/app_files_building/site-packages/foo.libs/libx.so",
            ],
        ),
    ])

    actual = build_link_map(_ctx(), actual_entries)

    # The important condition is that each lib*.so file is linked directly.
    expected_libs = {
        "bar/libs/liby.so": srcs[0],
        "foo.libs/libx.so": srcs[3],
    }
    env.expect.that_dict(actual[VenvSymlinkKind.LIB]).contains_at_least(expected_libs)

def _test_default_mode_directory_merge(name):
    analysis_test(
        name = name,
        impl = _test_default_mode_directory_merge_impl,
        target = "//python:none",
    )

_tests.append(_test_default_mode_directory_merge)

def _test_default_mode_directory_merge_impl(env, _):
    test_ctx = _ctx()
    srcs = [
        _file("pkg/site-packages/foo/__init__.py"),
        _file("pkg/site-packages/foo/gen_dir", is_directory = True),
        _file("pkg/site-packages/foo/bar.py"),
    ]
    entries = get_venv_symlinks(
        test_ctx,
        srcs,
        package = "foo",
        version_str = "1.0",
        site_packages_root = "pkg/site-packages",
    )
    env.expect.that_int(len(entries)).equals(1)
    env.expect.that_collection(entries[0].link_to_subpaths.to_list()).contains_exactly([])

    conflicting = _entry(
        "foo",
        "+other/site-packages/foo",
        [_file("../+other/site-packages/foo/other.py")],
    )
    merged = build_link_map(test_ctx, list(entries) + [conflicting])
    env.expect.that_dict(merged[VenvSymlinkKind.LIB]).contains_exactly({
        "foo/__init__.py": srcs[0],
        "foo/bar.py": srcs[2],
        "foo/gen_dir": srcs[1],
        "foo/other.py": _file("../+other/site-packages/foo/other.py"),
    })

    # Direct-link case: a directory File that is itself the top-level venv entry
    # must remain the File object (not a path string) after conflict merging so
    # default mode materializes a runfiles root_symlink rather than
    # ctx.actions.declare_symlink().
    direct_dir = _file("pkg/site-packages/foo", is_directory = True)
    direct_entries = get_venv_symlinks(
        test_ctx,
        [direct_dir],
        package = "foo",
        version_str = "1.0",
        site_packages_root = "pkg/site-packages",
    )
    env.expect.that_int(len(direct_entries)).equals(1)
    direct_merged = build_link_map(test_ctx, list(direct_entries) + [conflicting])
    env.expect.that_bool(types.is_string(direct_merged[VenvSymlinkKind.LIB]["foo"])).equals(False)
    env.expect.that_dict(direct_merged[VenvSymlinkKind.LIB]).contains_exactly({
        "foo": direct_dir,
        "foo/other.py": _file("../+other/site-packages/foo/other.py"),
    })

def _tree_venv_lib_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + "_srcs")
    args = ctx.actions.args()
    args.add_all("--output-dir", [out], expand_directories = False)
    for p in ctx.attr.paths:
        args.add("--path", p)
    for rel_path, content in ctx.attr.contents.items():
        args.add("--entry", "{}={}".format(rel_path, content))
    ctx.actions.run(
        executable = ctx.executable._populate_tree,
        arguments = [args],
        outputs = [out],
    )
    all_paths = sorted({p: True for p in ctx.attr.paths + ctx.attr.contents.keys()}.keys())
    entries = get_venv_symlinks(
        ctx,
        all_paths,
        package = ctx.attr.package,
        version_str = ctx.attr.version,
        site_packages_root = "site-packages",
        namespace_package_files = ctx.attr.namespace_package_files,
        tree_artifact = out,
    )
    builder = PyInfoBuilder.new()
    builder.transitive_sources.add([out])
    builder.venv_symlinks.add(entries)
    return [
        DefaultInfo(
            files = depset([out]),
            runfiles = ctx.runfiles(files = [out]),
        ),
        builder.build(),
    ]

tree_venv_lib = rule(
    implementation = _tree_venv_lib_impl,
    attrs = {
        "contents": attr.string_dict(),
        "namespace_package_files": attr.string_list(),
        "package": attr.string(mandatory = True),
        "paths": attr.string_list(),
        "version": attr.string(default = "1.0"),
        "_populate_tree": attr.label(
            default = ":populate_tree",
            executable = True,
            cfg = "exec",
        ),
    },
)

def _test_tree_artifact_rule_merging(name):
    rt_util.helper_target(
        tree_venv_lib,
        name = name + "_tree_a",
        package = "tree_a",
        paths = [
            "bin/tool_a",
            "site-packages/foo/__init__.py",
            "site-packages/foo/a.py",
            "site-packages/foo/plugins/shared.py",
            "site-packages/libnative.so",
            "site-packages/pkgutil_ns/__init__.py",
            "site-packages/pkgutil_ns/one.py",
        ],
        namespace_package_files = ["site-packages/pkgutil_ns/__init__.py"],
    )
    rt_util.helper_target(
        tree_venv_lib,
        name = name + "_tree_b",
        package = "tree_b",
        paths = [
            "site-packages/foo/plugins/b.py",
            "site-packages/foo/plugins/shared.py",
            "site-packages/pkgutil_ns/__init__.py",
            "site-packages/pkgutil_ns/two.py",
        ],
        namespace_package_files = ["site-packages/pkgutil_ns/__init__.py"],
    )
    rt_util.helper_target(
        py_library,
        name = name + "_combined",
        deps = [
            ":" + name + "_tree_a",
            ":" + name + "_tree_b",
        ],
    )
    analysis_test(
        name = name,
        impl = _test_tree_artifact_rule_merging_impl,
        target = name + "_combined",
    )

_tests.append(_test_tree_artifact_rule_merging)

def _test_tree_artifact_rule_merging_impl(env, target):
    entries = target[PyInfo].venv_symlinks.to_list()
    all_dirs = []
    for e in entries:
        for f in e.files.to_list():
            all_dirs.append(f.is_directory)
    env.expect.that_bool(all(all_dirs) and len(all_dirs) > 0).equals(True)

    test_ctx = _ctx(workspace_name = env.ctx.workspace_name)
    pkg = env.ctx.label.package
    tree_a_prefix = "{}/{}/{}_tree_a_srcs/".format(env.ctx.workspace_name, pkg, env.ctx.label.name)
    tree_b_prefix = "{}/{}/{}_tree_b_srcs/".format(env.ctx.workspace_name, pkg, env.ctx.label.name)

    merged = build_link_map(test_ctx, entries)
    env.expect.that_dict(merged[VenvSymlinkKind.LIB]).contains_exactly({
        "foo/__init__.py": tree_a_prefix + "site-packages/foo/__init__.py",
        "foo/a.py": tree_a_prefix + "site-packages/foo/a.py",
        "foo/plugins/b.py": tree_b_prefix + "site-packages/foo/plugins/b.py",
        "foo/plugins/shared.py": tree_a_prefix + "site-packages/foo/plugins/shared.py",
        "libnative.so": tree_a_prefix + "site-packages/libnative.so",
        "pkgutil_ns/__init__.py": tree_a_prefix + "site-packages/pkgutil_ns/__init__.py",
        "pkgutil_ns/one.py": tree_a_prefix + "site-packages/pkgutil_ns/one.py",
        "pkgutil_ns/two.py": tree_b_prefix + "site-packages/pkgutil_ns/two.py",
    })
    env.expect.that_dict(merged[VenvSymlinkKind.BIN]).contains_exactly({
        "tool_a": tree_a_prefix + "bin/tool_a",
    })

def app_files_building_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
