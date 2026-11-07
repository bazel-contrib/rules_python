"""dependency_groups tests"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:dependency_groups.bzl", "select_dependency_groups")  # buildifier: disable=bzl-visibility

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
        (["*"], ["dev_pkg", "docs_pkg", "grpc_pkg", "main_pkg", "shared_pkg", "test_pkg"]),
    ]:
        got, failures = _select(specs)
        env.expect.where(specs = specs).that_collection(failures).contains_exactly([])
        env.expect.where(specs = specs).that_collection(got.packages).contains_exactly(want).in_order()
        env.expect.where(specs = specs).that_bool(got.all).equals(False)

_tests.append(_test_select)

def _test_select_all(env):
    got, failures = _select(["*", "transitive"])
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_bool(got.all).equals(True)
    env.expect.that_collection(got.packages).contains_exactly([])

_tests.append(_test_select_all)

def _test_select_errors(env):
    for specs, want in [
        (["missing"], "Unknown dependency group 'missing'. Available groups: default, group:dev, group:test, optional:all, optional:docs, optional:grpc"),
        (["default", "transitive"], "The 'transitive' dependency group specifier is only supported together with '*', which selects all of the packages, got: [\"default\", \"transitive\"]"),
    ]:
        _, failures = _select(specs)
        env.expect.where(specs = specs).that_collection(failures).contains_exactly([want])

_tests.append(_test_select_errors)

def _test_include_group_errors(env):
    for groups, want in [
        ({"a": [{"include-group": "missing"}]}, "Unknown dependency group 'missing' included from 'a'"),
        ({"a": [{"include-group": "b"}], "b": [{"include-group": "a"}]}, "Cyclic dependency group includes: a, b"),
    ]:
        _, failures = _select(["*"], pyproject = struct(
            name = None,
            dependencies = [],
            optional_dependencies = {},
            dependency_groups = groups,
        ))
        env.expect.that_collection(failures).contains_exactly([want])

_tests.append(_test_include_group_errors)

def dependency_groups_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
