"""Conformance tests that use the cases from the `packaging` project.

The cases in `packaging_cases.bzl` are generated, see
`//tests/support/pypa_packaging`.
"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:normalize_name.bzl", "normalize_name")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:pep508_evaluate.bzl", "evaluate")  # buildifier: disable=bzl-visibility
load(
    ":packaging_cases.bzl",
    "EVALUATE_CASES",
    "INVALID_MARKERS",
    "LOGIC_CASES",
    "MARKER_ENV",
    "MARKER_TABLE",
    "SET_ENV_VALUE",
    "SET_TABLE",
)

_SET_VARIABLES = ["dependency_groups", "extras"]

_tests = []

def _env(overrides = {}):
    env = dict(MARKER_ENV) | overrides | {
        "_aliases": {name: normalize_name for name in ["extra"] + _SET_VARIABLES},
    }

    # The names in the environment are expected to be already normalized.
    env["extra"] = normalize_name(env["extra"])
    for name in _SET_VARIABLES:
        env[name] = [normalize_name(value) for value in SET_ENV_VALUE]
    return env

def _test_packaging_evaluate(env):
    failures = []
    for marker, overrides, want in EVALUATE_CASES:
        got = evaluate(marker, env = _env(json.decode(overrides)))
        if got != want:
            failures.append("{} with {}: got {}, want {}".format(marker, overrides, got, want))

    env.expect.that_collection(failures).contains_exactly([])

_tests.append(_test_packaging_evaluate)

def _test_packaging_invalid_markers(env):
    failures = [
        marker
        for marker in INVALID_MARKERS
        if evaluate(marker, env = _env(), _fail = lambda _: "invalid") != "invalid"
    ]
    env.expect.that_collection(failures).contains_exactly([])

_tests.append(_test_packaging_invalid_markers)

def _test_packaging_marker_table(env):
    failures = []
    marker_env = _env()
    for variable, op, value, results in MARKER_TABLE + SET_TABLE:
        for marker, result in [
            ('{} {} "{}"'.format(variable, op, value), results[0]),
            ('"{}" {} {}'.format(value, op, variable), results[1]),
        ]:
            want = {"E": "error", "F": False, "T": True}[result]
            got = evaluate(marker, env = marker_env, _fail = lambda _: "error")
            if got != want:
                failures.append("{}: got {}, want {}".format(marker, got, want))

    env.expect.that_collection(failures).contains_exactly([])

_tests.append(_test_packaging_marker_table)

def _test_packaging_logic(env):
    failures = []
    marker_env = _env()
    for marker, want in LOGIC_CASES:
        got = evaluate(marker, env = marker_env)
        if got != want:
            failures.append("{}: got {}, want {}".format(marker, got, want))

    env.expect.that_collection(failures).contains_exactly([])

_tests.append(_test_packaging_logic)

def packaging_conformance_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )
