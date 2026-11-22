"""dependency_groups tests"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load(
    "//python/private/pypi:dependency_groups.bzl",
    "select_dependency_groups",
)  # buildifier: disable=bzl-visibility

_tests = []

_PYPROJECT = struct(
    name = "my-project",
    dependencies = ["main-pkg>=1.0"],
    optional_dependencies = {
        "Docs": ["docs-pkg"],
        "all": ["My_Project[docs, grpc]"],
        "grpc": ["grpc-pkg"],
    },
    dependency_groups = {
        "dev": ["dev-pkg", "shared-pkg", {"include-group": "Test"}],
        "test": ["test_pkg", "shared-pkg"],
    },
)

def _select(specs, pyproject = _PYPROJECT):
    failures = []
    got = select_dependency_groups(pyproject, specs, _fail = failures.append)
    return got, failures

def _test_select(env):
    for specs, want in [
        (["default"], ["main_pkg"]),
        (["optional:docs"], ["docs_pkg"]),
        (["group:test"], ["shared_pkg", "test_pkg"]),
        (["dev"], ["dev_pkg", "shared_pkg", "test_pkg"]),
        (["grpc"], ["grpc_pkg"]),
        (["all"], ["docs_pkg", "grpc_pkg"]),
        (["optional:*"], ["docs_pkg", "grpc_pkg"]),
        (["group:*"], ["dev_pkg", "shared_pkg", "test_pkg"]),
        (["default", "group:test"], ["main_pkg", "shared_pkg", "test_pkg"]),
        (
            ["*"],
            [
                "dev_pkg",
                "docs_pkg",
                "grpc_pkg",
                "main_pkg",
                "shared_pkg",
                "test_pkg",
            ],
        ),
    ]:
        got, failures = _select(specs)
        env.expect.where(specs = specs).that_collection(
            failures,
        ).contains_exactly([])
        env.expect.where(specs = specs).that_collection(
            got.packages,
        ).contains_exactly(want).in_order()
        env.expect.where(specs = specs).that_bool(got.all).equals(False)

_tests.append(_test_select)

def _test_self_reference_extras(env):
    pyproject = struct(
        name = "my-project",
        dependencies = [],
        optional_dependencies = {
            "a": ["a-pkg", "my-project[b]"],
            "all": ["My_Project[docs, grpc]"],
            "b": ["b-pkg", "my-project[a]"],
            "docs": ["docs-pkg"],
            "everything": ["my-project[all]", "my-project"],
            "grpc": ["grpc-pkg"],
        },
        dependency_groups = {
            "ci": ["ci-pkg", "my-project[all]"],
        },
    )
    for specs, want in [
        (["everything"], ["docs_pkg", "grpc_pkg"]),
        (["ci"], ["ci_pkg", "docs_pkg", "grpc_pkg"]),
        (["a"], ["a_pkg", "b_pkg"]),
    ]:
        got, failures = _select(specs, pyproject = pyproject)
        env.expect.where(specs = specs).that_collection(
            failures,
        ).contains_exactly([])
        env.expect.where(specs = specs).that_collection(
            got.packages,
        ).contains_exactly(want).in_order()

_tests.append(_test_self_reference_extras)

def _test_select_all(env):
    got, failures = _select(["*", "transitive"])
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_bool(got.all).equals(True)
    env.expect.that_collection(got.packages).contains_exactly([])

_tests.append(_test_select_all)

def _test_select_extras(env):
    pyproject = struct(
        name = "my-project",
        dependencies = ["main-pkg[Foo_Bar, baz]>=1.0", "plain-pkg"],
        optional_dependencies = {
            "all": ["my-project[docs]"],
            "docs": ["docs-pkg[extra]", "main-pkg[docs]"],
        },
        dependency_groups = {
            "dev": ["dev-pkg[cli]", {"include-group": "test"}],
            "test": [
                "test-pkg[cov]; sys_platform == 'linux'",
                "test-pkg[win]; sys_platform == 'win32'",
                "test-pkg[cov]",
            ],
        },
    )
    for specs, want in [
        (["default"], {"main_pkg": {(): ["baz", "foo_bar"]}}),
        # The markers of the requirements are kept, so that the extras can be
        # added only for the platforms that request them.
        (["dev"], {
            "dev_pkg": {(): ["cli"]},
            "test_pkg": {
                (): ["cov"],
                ("sys_platform == 'linux'",): ["cov"],
                ("sys_platform == 'win32'",): ["win"],
            },
        }),
        # The extras of the self reference are the optional dependencies of
        # the project, not the extras of a package.
        (["all"], {"docs_pkg": {(): ["extra"]}, "main_pkg": {(): ["docs"]}}),
        (["default", "docs"], {
            "docs_pkg": {(): ["extra"]},
            "main_pkg": {(): ["baz", "docs", "foo_bar"]},
        }),
    ]:
        got, failures = _select(specs, pyproject = pyproject)
        env.expect.where(specs = specs).that_collection(failures).contains_exactly([])
        env.expect.where(specs = specs).that_dict(got.extras).contains_exactly(want)

    # The extras of all of the groups are returned when everything is selected.
    got, failures = _select(["*", "transitive"], pyproject = pyproject)
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_bool(got.all).equals(True)
    env.expect.that_collection(got.packages).contains_exactly([])
    env.expect.that_dict(got.extras).keys().contains_exactly([
        "dev_pkg",
        "docs_pkg",
        "main_pkg",
        "test_pkg",
    ])

_tests.append(_test_select_extras)

def _test_select_extras_self_reference_markers(env):
    pyproject = struct(
        name = "my-project",
        dependencies = [
            "my-project[win]; sys_platform == 'win32'",
            "my-project[cycle]; python_version < '3.12'",
        ],
        optional_dependencies = {
            "cycle": ["my-project[win]", "my-project[cycle]", "cycle-pkg[c]"],
            "win": [
                "win-pkg[a]",
                "win-pkg[b]; python_version < '3.12'",
                "my-project[cycle]",
            ],
        },
        dependency_groups = {},
    )

    # The requirements of a group that is selected by a self reference with a
    # marker are only requested if the marker is true.
    got, failures = _select(["default"], pyproject = pyproject)
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_collection(got.packages).contains_exactly(["cycle_pkg", "win_pkg"])
    env.expect.that_dict(got.extras).contains_exactly({
        "cycle_pkg": {
            ("python_version < '3.12'",): ["c"],
            ("sys_platform == 'win32'",): ["c"],
        },
        "win_pkg": {
            ("python_version < '3.12'",): ["a", "b"],
            ("python_version < '3.12'", "sys_platform == 'win32'"): ["b"],
            ("sys_platform == 'win32'",): ["a"],
        },
    })

    # Selecting the group directly requests it on all of the platforms.
    got, failures = _select(["default", "win"], pyproject = pyproject)
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got.extras["win_pkg"]).contains_at_least({
        (): ["a"],
        ("python_version < '3.12'",): ["b"],
    })

_tests.append(_test_select_extras_self_reference_markers)

def _test_select_empty_wildcards(env):
    pyproject = struct(
        name = "my-project",
        dependencies = ["main-pkg"],
        optional_dependencies = {},
        dependency_groups = {},
    )
    for specs, want in [
        (["optional:*"], []),
        (["group:*"], []),
        (["*"], ["main_pkg"]),
    ]:
        got, failures = _select(specs, pyproject = pyproject)
        env.expect.where(specs = specs).that_collection(failures).contains_exactly([])
        env.expect.where(specs = specs).that_collection(got.packages).contains_exactly(want)

_tests.append(_test_select_empty_wildcards)

def _test_select_errors(env):
    for specs, want in [
        (
            ["missing"],
            "Unknown dependency group 'missing'. Available groups: default, group:dev, group:test, optional:all, optional:docs, optional:grpc",
        ),
        (
            ["default", "transitive"],
            "The 'transitive' dependency group specifier is only supported together with '*', which selects all of the packages, got: [\"default\", \"transitive\"]",
        ),
    ]:
        got, failures = _select(specs)
        env.expect.where(specs = specs).that_str(got).equals(None)
        env.expect.where(specs = specs).that_collection(
            failures,
        ).contains_exactly([want])

_tests.append(_test_select_errors)

def _test_include_group_errors(env):
    for groups, want in [
        (
            {"a": [{"include-group": "missing"}]},
            "Unknown dependency group 'missing' included from 'a'",
        ),
        (
            {"a": [{"include-group": "b"}], "b": [{"include-group": "a"}]},
            "Cyclic dependency group includes: a, b",
        ),
    ]:
        got, failures = _select(["a"], pyproject = struct(
            name = None,
            dependencies = [],
            optional_dependencies = {},
            dependency_groups = groups,
        ))
        env.expect.that_str(got).equals(None)
        env.expect.that_collection(failures).contains_exactly([want])

_tests.append(_test_include_group_errors)

def dependency_groups_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
