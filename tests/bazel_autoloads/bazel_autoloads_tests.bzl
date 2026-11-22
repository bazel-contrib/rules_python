"""Tests for the `.bzl` files that Bazel 8 autoloads from `rules_python`."""

load("@bazel_skylib//:bzl_library.bzl", "StarlarkLibraryInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")

# The `bzl_library` targets in `//python` of the files that Bazel 8 loads in
# order to autoload the Python rules and providers, see `AUTOLOAD_CONFIG` in
# https://github.com/bazelbuild/bazel/blob/release-8.9.0/src/main/java/com/google/devtools/build/lib/packages/AutoloadSymbols.java
_AUTOLOADED = [
    "py_binary",
    "py_cc_link_params_info",
    "py_info",
    "py_library",
    "py_runtime",
    "py_runtime_info",
    "py_test",
]

# The repositories where Bazel 8 does not use the autoloads, see
# `PREDECLARED_REPOS_DISALLOWING_AUTOLOADS` in the file above. The repositories
# created by the module extensions of these modules are included, because
# only the part of the canonical name that is before the first `+` is used.
#
# A `.bzl` file from any other repository cannot be loaded by the autoloaded
# files, because Bazel would need the autoloaded symbols in order to load it,
# which is reported as `Cycle caused by autoloads`. The users can only work
# this around with the `--repositories_without_autoloads` flag.
_REPOS_WITHOUT_AUTOLOADS = {
    # The main repository, i.e. `rules_python` itself
    "": None,
    "apple_support": None,
    "bazel_features": None,
    "bazel_features_globals": None,
    "bazel_features_version": None,
    "bazel_skylib": None,
    "bazel_tools": None,
    "build_bazel_apple_support": None,
    "cc_compatibility_proxy": None,
    "com_google_protobuf": None,
    "compatibility_proxy": None,
    "proto_bazel_features": None,
    "protobuf": None,
    "rules_android": None,
    "rules_cc": None,
    "rules_java": None,
    "rules_java_builtin": None,
    "rules_python": None,
    "rules_python_internal": None,
    "rules_shell": None,
}

_tests = []

# NOTE: This is why the autoloaded files, e.g. `py_library.bzl` and
# `py_runtime_rule.bzl`, do not use `@pypackaging.bzl` to parse and normalize
# the versions. If we want to fully use it in those files, `pypackaging.bzl`
# first needs to be added to the list of repositories without autoloads in
# Bazel.
def _test_autoloaded_files_only_load_from_repos_without_autoloads(name):
    analysis_test(
        name = name,
        impl = _test_autoloaded_files_only_load_from_repos_without_autoloads_impl,
        targets = {
            lib: "//python:" + lib
            for lib in _AUTOLOADED
        },
    )

def _test_autoloaded_files_only_load_from_repos_without_autoloads_impl(env, targets):
    for lib in _AUTOLOADED:
        target = getattr(targets, lib)
        got = []
        for src in target[StarlarkLibraryInfo].transitive_srcs.to_list():
            repo = src.owner.workspace_name

            # Bzlmod uses `+` (`~` before Bazel 8) to separate the module name
            # from the rest of the canonical repository name.
            repo, _, _ = repo.partition("+")
            repo, _, _ = repo.partition("~")
            if repo not in _REPOS_WITHOUT_AUTOLOADS:
                got.append(str(src.owner))

        env.expect.that_collection(
            got,
            expr = "files loaded by {} from repos with autoloads".format(target.label),
        ).contains_exactly([])

_tests.append(_test_autoloaded_files_only_load_from_repos_without_autoloads)

def bazel_autoloads_test_suite(name):
    test_suite(
        name = name,
        tests = _tests,
    )
