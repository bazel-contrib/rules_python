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
            "test": ["test-pkg[cov]; sys_platform == 'linux'"],
        },
    )
    for specs, want in [
        (["default"], {"main_pkg": ["baz", "foo_bar"]}),
        (["dev"], {"dev_pkg": ["cli"], "test_pkg": ["cov"]}),
        # The extras of the self reference are the optional dependencies of
        # the project, not the extras of a package.
        (["all"], {"docs_pkg": ["extra"], "main_pkg": ["docs"]}),
        (["default", "docs"], {"docs_pkg": ["extra"], "main_pkg": ["baz", "docs", "foo_bar"]}),
        (["*", "transitive"], {
            "dev_pkg": ["cli"],
            "docs_pkg": ["extra"],
            "main_pkg": ["baz", "docs", "foo_bar"],
            "test_pkg": ["cov"],
        }),
    ]:
        got, failures = _select(specs, pyproject = pyproject)
        env.expect.where(specs = specs).that_collection(failures).contains_exactly([])
        env.expect.where(specs = specs).that_dict(got.extras).contains_exactly(want)

_tests.append(_test_select_extras)

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
