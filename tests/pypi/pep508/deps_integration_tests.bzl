""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@whl_metadata_parsing_tests//:defs.bzl", "HOST_PLATFORM", "METADATA", "WANT")
load("//python/private:normalize_name.bzl", "normalize_name")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:pep508_deps.bzl", "deps")  # buildifier: disable=bzl-visibility

_tests = []

def _test_compare_python_star_implementation(env):
    target_platforms = [HOST_PLATFORM]

    for pkg, want_deps_by_version in WANT.items():
        name = normalize_name(pkg)
        metadata = METADATA[name]
        for python_version, want_deps in want_deps_by_version.items():
            got = deps(
                name = name,
                requires_dist = metadata["requires_dist"],
                platforms = target_platforms,
                excludes = [],
                extras = [],
                default_python_version = python_version,
            ).deps
            env.expect.that_collection(got).contains_exactly(want_deps)

_tests.append(_test_compare_python_star_implementation)

def deps_integration_test_suite(name):  # buildifier: disable=function-docstring
    test_suite(
        name = name,
        basic_tests = _tests,
    )
