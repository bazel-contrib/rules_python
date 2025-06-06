""

load("@rules_testing//lib:test_suite.bzl", "test_suite")

_tests = []

def _test_simple(env, order, want1, want2):
    c1 = depset(
        ["c1"],
        order = order,
    )
    c2 = depset(
        ["c2"],
        order = order,
    )
    b = depset(
        ["b"],
        transitive = [c1],
        order = order,
    )
    a1 = depset(
        ["a1"],
        transitive = [c2, b],
        order = order,
    )
    a2 = depset(
        ["a2"],
        transitive = [b, c2],
        order = order,
    )

    got1 = a1.to_list()
    got2 = a2.to_list()

    env.expect.that_collection(got1).contains_exactly(want1).in_order()
    env.expect.that_collection(got2).contains_exactly(want2).in_order()

def _test_preorder(env):
    _test_simple(
        env,
        "preorder",
        [
            "a1",
            "c2",
            "b",
            "c1",
        ],
        [
            "a2",
            "b",
            "c1",
            "c2",
        ],
    )

_tests.append(_test_preorder)

def _test_postorder(env):
    _test_simple(
        env,
        "postorder",
        [
            "c2",
            "c1",
            "b",
            "a1",
        ],
        [
            "c1",
            "b",
            "c2",
            "a2",
        ],
    )

_tests.append(_test_postorder)

def _test_topological(env):
    _test_simple(
        env,
        "topological",
        [
            "a1",
            "c2",
            "b",
            "c1",
        ],
        [
            "a2",
            "b",
            "c1",
            "c2",
        ],
    )

_tests.append(_test_topological)

def depset_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
