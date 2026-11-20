"""Conformance tests that use the cases from the `packaging` project.

The cases in `packaging_cases.bzl` are generated, see
`//tests/support/pypa_packaging`.
"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:version.bzl", "version")  # buildifier: disable=bzl-visibility
load(
    ":packaging_cases.bzl",
    "NORMALIZED_VERSIONS",
    "ORDERED_VERSIONS",
)

_tests = []

def _test_packaging_normalized_versions(env):
    failures = []
    for input, want in NORMALIZED_VERSIONS:
        got = version.normalize(input)
        if got != want:
            failures.append("normalize({}): got {}, want {}".format(input, got, want))

        got = version.parse(input, strict = True).string
        if got != want:
            failures.append("parse({}).string: got {}, want {}".format(input, got, want))

    env.expect.that_collection(failures).contains_exactly([])

_tests.append(_test_packaging_normalized_versions)

def _test_packaging_ordering(env):
    keys = [version.key(version.parse(v, strict = True)) for v in ORDERED_VERSIONS]
    failures = []
    for i, lower in enumerate(keys):
        for j in range(i + 1, len(keys)):
            if not lower < keys[j]:
                failures.append("{} < {}".format(ORDERED_VERSIONS[i], ORDERED_VERSIONS[j]))

    env.expect.that_collection(failures).contains_exactly([
        # TODO: fix the known failures
        "1!1.0a1.dev1+local < 1!1.0a1",
        "1.0a1.dev1+local < 1.0a1",
    ])

_tests.append(_test_packaging_ordering)

def packaging_conformance_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )
