""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:labels.bzl", "requirement_label", "requirement_labels")  # buildifier: disable=bzl-visibility

_tests = []

_TMPL = "@@pypi//{}:{}"

def _test_requirement_label(env):
    for requirement, want in {
        "Foo.Bar": "@@pypi//foo_bar:pkg",
        "foo[ grpc ]": "@@pypi//foo:[grpc]",
        "foo[Async-Rest]": "@@pypi//foo:[async_rest]",
        "foo[]": "@@pypi//foo:[]",
        "foo[grpc]": "@@pypi//foo:[grpc]",
    }.items():
        env.expect.where(requirement = requirement).that_str(requirement_label(_TMPL, requirement)).equals(want)

_tests.append(_test_requirement_label)

def _test_requirement_label_multiple_extras_fails(env):
    errors = []
    requirement_label(
        _TMPL,
        "google-api-core[grpc,async_rest]",
        fail = lambda msg: errors.append(msg),
    )
    env.expect.that_collection(errors).has_size(1)
    env.expect.that_str(errors[0]).contains("requirements(\"google-api-core[grpc,async_rest]\")")

_tests.append(_test_requirement_label_multiple_extras_fails)

def _test_requirement_labels(env):
    env.expect.that_collection(
        requirement_labels(_TMPL, "google-api-core[grpc, async_rest]", "foobar[baz]", "foo", "bar[]"),
    ).contains_exactly([
        "@@pypi//google_api_core:[async_rest]",
        "@@pypi//google_api_core:[grpc]",
        "@@pypi//foobar:[baz]",
        "@@pypi//foo:pkg",
        "@@pypi//bar:[]",
    ]).in_order()

_tests.append(_test_requirement_labels)

def labels_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
