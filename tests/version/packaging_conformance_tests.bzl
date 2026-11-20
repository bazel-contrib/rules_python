"""Conformance tests that use the cases from the `packaging` project.

The cases in `packaging_cases.bzl` are generated, see
`//tests/support/pypa_packaging`.
"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:version.bzl", "version")  # buildifier: disable=bzl-visibility
load(
    ":packaging_cases.bzl",
    "MATRIX",
    "MATRIX_VERSIONS",
    "NORMALIZED_VERSIONS",
    "ORDERED_VERSIONS",
    "SPECIFIER_CASES",
)

_tests = []

_OPERATORS = {
    "!=": version.is_ne,
    "<": version.is_lt,
    "<=": version.is_le,
    "==": version.is_eq,
    "===": version.is_eeq,
    ">": version.is_gt,
    ">=": version.is_ge,
    "~=": version.is_compatible,
}

def _matches(candidate, op, spec):
    """Evaluate `candidate <op> spec` like a version specifier would."""
    return _OPERATORS[op](
        version.parse(candidate, strict = True),
        # Only the specifier can use the `.*` suffix.
        version.parse(spec, strict = False),
    )

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

    env.expect.that_collection(failures).contains_exactly([])

_tests.append(_test_packaging_ordering)

def _test_packaging_specifiers(env):
    failures = []
    for candidate, op, spec, want in SPECIFIER_CASES:
        if _matches(candidate, op, spec) != want:
            failures.append("{} {} {}: want {}".format(candidate, op, spec, want))

    env.expect.that_collection(failures).contains_exactly([])

_tests.append(_test_packaging_specifiers)

def _test_packaging_specifier_matrix(env):
    failures = []
    for op, spec, row in MATRIX:
        for i, candidate in enumerate(MATRIX_VERSIONS):
            want = row[i] == "T"
            if _matches(candidate, op, spec) != want:
                failures.append("{} {} {}: want {}".format(candidate, op, spec, want))

    env.expect.that_collection(failures).contains_exactly([])

_tests.append(_test_packaging_specifier_matrix)

def packaging_conformance_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )
