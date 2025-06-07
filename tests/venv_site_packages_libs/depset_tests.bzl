"""Characterization tests for depset behaviour.

This is checking how we can override packages without properly and it seems that the order of the
depset does not matter. As long as the third party deps come first, it will work.
"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")

_tests = []

def _test_simple(env, order, want1, want2):
    c1 = depset(["c1"], order = order)
    c2 = depset(["c2"], order = order)
    e1 = depset(["e1"], order = order)
    e2 = depset(["e2"], order = order)
    d1 = depset(["d1"], transitive = [e1, c1], order = order)
    d2 = depset(["d2"], transitive = [e2, c2], order = order)
    b = depset(["b"], transitive = [c1, d1], order = order)
    a1 = depset(["override_first"], transitive = [c2, d2, b], order = order)
    a2 = depset(["override_last"], transitive = [b, c2, d2], order = order)

    def _first_leters(sequence):
        ret = {}
        for item in sequence:
            ret.setdefault(item[0], item)

        # return the values sorted
        return sorted(ret.values(), key = lambda x: (not x.startswith("override"), x))

    got1 = _first_leters(a1.to_list())
    got2 = _first_leters(a2.to_list())

    env.expect.that_collection(got1).contains_exactly(want1).in_order()
    env.expect.that_collection(got2).contains_exactly(want2).in_order()

def _test_preorder(env):
    _test_simple(
        env,
        "preorder",
        ["override_first", "b", "c2", "d2", "e2"],
        ["override_last", "b", "c1", "d1", "e1"],
    )

_tests.append(_test_preorder)

def _test_postorder(env):
    _test_simple(
        env,
        "postorder",
        ["override_first", "b", "c2", "d2", "e2"],
        ["override_last", "b", "c1", "d1", "e1"],
    )

_tests.append(_test_postorder)

def _test_topological(env):
    _test_simple(
        env,
        "topological",
        ["override_first", "b", "c2", "d2", "e2"],
        ["override_last", "b", "c1", "d1", "e1"],
    )

_tests.append(_test_topological)

def depset_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
