""

load("@rules_testing//lib:test_suite.bzl", "test_suite")

_tests = []

def _test_simple(env):
    c1 = depset(
        ["c1"],
        order = "topological",
    )
    c2 = depset(
        ["c2"],
        order = "topological",
    )
    b = depset(
        ["b"],
        transitive = [c1],
        order = "topological",
    )
    a1 = depset(
        ["A"],
        transitive = [c2, b],
        order = "topological",
    )
    a2 = depset(
        ["A"],
        transitive = [b, c2],
        order = "topological",
    )

    got1 = a1.to_list()
    got2 = a2.to_list()

    env.expect.that_collection(got1).contains_exactly(
        ["A", "c2", "b", "c1"],
    ).in_order()
    env.expect.that_collection(got2).contains_exactly(
        ["A", "b", "c1", "c2"],
    ).in_order()

_tests.append(_test_simple)

def depset_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
