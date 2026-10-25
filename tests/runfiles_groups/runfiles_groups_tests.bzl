"""Tests for what ends up in which runfiles group."""

load("@bazel_features//:features.bzl", "bazel_features")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_binary.bzl", "py_binary")
load("//python:py_library.bzl", "py_library")
load("//python/private:common_labels.bzl", "labels")  # buildifier: disable=bzl-visibility
load("//tests/support:support.bzl", "NOT_WINDOWS")
load(":test_rules.bzl", "ResolvedGroupsInfo", "bucket_ml", "resolved_groups")

# Packagers walk the Python toolchain through toolchains_aspects, which takes
# "*" since Bazel 8.8.0 and a propagation filter since Bazel 9.0.0.
WALKS_TOOLCHAINS = [] if (
    bazel_features.rules.aspect_propagation_context or
    bazel_features.rules.supports_toolchains_aspects_star
) else ["@platforms//:incompatible"]

_tests = []

def _test_namespace_package_venv_links(name):
    # Both distributions ship nspkg/__init__.py, like pkgutil-style namespace
    # packages, so the venv can't link nspkg as one directory.
    for distribution, module in [("ns_alpha", "alpha"), ("ns_beta", "beta")]:
        rt_util.helper_target(
            py_library,
            name = name + "_" + distribution,
            srcs = [
                "{}/site-packages/nspkg/__init__.py".format(distribution),
                "{}/site-packages/nspkg/{}.py".format(distribution, module),
            ],
            data = ["{0}/site-packages/{0}-1.0.dist-info/METADATA".format(distribution)],
            experimental_venvs_site_packages = "//python/config_settings:venvs_site_packages",
            imports = ["{}/site-packages".format(distribution)],
        )
    rt_util.helper_target(
        py_binary,
        name = name + "_bin",
        srcs = ["main.py"],
        main = "main.py",
        deps = [name + "_ns_alpha", name + "_ns_beta"],
    )
    rt_util.helper_target(
        resolved_groups,
        name = name + "_subject",
        binary = name + "_bin",
    )
    analysis_test(
        name = name,
        impl = _test_namespace_package_venv_links_impl,
        target = name + "_subject",
        config_settings = {
            labels.BOOTSTRAP_IMPL: "script",
            labels.VENVS_SITE_PACKAGES: "yes",
        },
        attr_values = {"target_compatible_with": WALKS_TOOLCHAINS + NOT_WINDOWS},
    )

def _test_namespace_package_venv_links_impl(env, target):
    groups = target[ResolvedGroupsInfo].groups

    for distribution, module in [("ns_alpha", "alpha"), ("ns_beta", "beta")]:
        env.expect.that_collection(
            groups["rules_python#pypi/" + distribution].root_symlinks,
        ).contains_predicate(matching.str_endswith("site-packages/nspkg/{}.py".format(module)))

    binary = groups[str(target.label).removesuffix("_subject") + "_bin"]
    env.expect.that_collection(binary.root_symlinks).not_contains_predicate(
        matching.str_matches("*site-packages/nspkg/*"),
    )

_tests.append(_test_namespace_package_venv_links)

def _test_configure_with_aspect_hints(name):
    rt_util.helper_target(bucket_ml, name = name + "_bucket_ml")
    rt_util.helper_target(
        py_binary,
        name = name + "_bin",
        srcs = ["main.py"],
        main = "main.py",
        deps = [":foo_pkg"],
        aspect_hints = [name + "_bucket_ml"],
    )
    rt_util.helper_target(
        resolved_groups,
        name = name + "_subject",
        binary = name + "_bin",
    )
    analysis_test(
        name = name,
        impl = _test_configure_with_aspect_hints_impl,
        target = name + "_subject",
        attr_values = {"target_compatible_with": WALKS_TOOLCHAINS},
    )

def _test_configure_with_aspect_hints_impl(env, target):
    foo_pkg = target[ResolvedGroupsInfo].groups["rules_python#pypi/foo_pkg"]
    env.expect.that_str(foo_pkg.merge_affinity).equals("ml")
    env.expect.that_bool(foo_pkg.do_not_merge).equals(True)

_tests.append(_test_configure_with_aspect_hints)

def runfiles_groups_test_suite(name):
    test_suite(name = name, tests = _tests)
