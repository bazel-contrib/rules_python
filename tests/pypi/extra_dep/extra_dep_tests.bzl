"""Tests for the extra_dep and extra_select rules."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_info.bzl", "PyInfo")
load("//python:py_library.bzl", "py_library")
load("//python/private:common_labels.bzl", "labels")  # buildifier: disable=bzl-visibility
load("//python/private:py_cc_link_params_info.bzl", "PyCcLinkParamsInfo")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:env_marker_setting.bzl", "env_marker_setting")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:extra_dep.bzl", "extra_dep", "extra_select_targets")  # buildifier: disable=bzl-visibility

_tests = []
_basic_tests = []

def _py_library(name, **kwargs):
    """A py_library with a generated source to check the output configuration."""
    rt_util.helper_target(
        native.genrule,
        name = name + "_gen",
        outs = [name + ".py"],
        cmd = "touch $@",
    )
    rt_util.helper_target(
        py_library,
        name = name,
        srcs = [name + ".py"],
        **kwargs
    )

def _pkg(name, extras = {}):
    """Create the targets of a package like the whl repositories do.

    Args:
        name: the name of the package, the `<name>_extras` target is created
            for the packages that depend on its extras.
        extras: the extras to the dependencies of the extra.
    """
    _py_library(name)
    for extra, deps in extras.items():
        rt_util.helper_target(
            py_library,
            name = "{}[{}]".format(name, extra),
            deps = [name] + deps,
        )

    extra_select_targets(
        name = name + "_extras",
        targets = {extra: "{}[{}]".format(name, extra) for extra in extras},
        default = name,
        distribution = name + " 1.0",
        visibility = ["//visibility:private"],
    )

def _extra_dep(name, pkg, extra):
    rt_util.helper_target(
        extra_dep,
        name = name,
        deps = [pkg + "_extras"],
        extra = extra,
    )

def _sources(target):
    return sorted([f.basename for f in target[PyInfo].transitive_sources.to_list()])

def _test_extra(name):
    _py_library(name + "_dep_a")
    _pkg(name + "_foo", {"a": [name + "_dep_a"]})
    _extra_dep(name + "_subject", name + "_foo", "a")
    analysis_test(
        name = name,
        impl = _test_extra_impl,
        target = name + "_subject",
    )

def _test_extra_impl(env, target):
    env.expect.that_collection(_sources(target)).contains_exactly([
        "test_extra_dep_a.py",
        "test_extra_foo.py",
    ])

    # The setting is reset, so the targets of the extra are analyzed in the
    # same configuration as the target that depends on the extra.
    env.expect.that_collection({
        f.root.path: None
        for f in target[PyInfo].transitive_sources.to_list()
    }.keys()).contains_exactly([env.ctx.bin_dir.path])

_tests.append(_test_extra)

def _test_unknown_extra(name):
    _py_library(name + "_dep_a")
    _pkg(name + "_foo", {"a": [name + "_dep_a"]})
    _extra_dep(name + "_subject", name + "_foo", "unknown")
    analysis_test(
        name = name,
        impl = _test_unknown_extra_impl,
        target = name + "_subject",
    )

def _test_unknown_extra_impl(env, target):
    # Like `pip`, the extras that the package does not provide are ignored and
    # a warning is printed.
    env.expect.that_collection(_sources(target)).contains_exactly([
        "test_unknown_extra_foo.py",
    ])

_tests.append(_test_unknown_extra)

def _test_no_extras(name):
    _pkg(name + "_foo")
    _extra_dep(name + "_subject", name + "_foo", "a")
    analysis_test(
        name = name,
        impl = _test_no_extras_impl,
        target = name + "_subject",
    )

def _test_no_extras_impl(env, target):
    env.expect.that_collection(_sources(target)).contains_exactly([
        "test_no_extras_foo.py",
    ])

_tests.append(_test_no_extras)

def _test_different_extras_of_the_same_package(name):
    # Both `p` and `q` depend on `c`, but each of them gets only the
    # dependencies of the extra that it requests.
    _py_library(name + "_tomli")
    _py_library(name + "_other_dep")
    _pkg(name + "_c", {
        "other": [name + "_other_dep"],
        "toml": [name + "_tomli"],
    })
    _extra_dep(name + "_p_c[toml]", name + "_c", "toml")
    _extra_dep(name + "_q_c[other]", name + "_c", "other")
    _py_library(name + "_p", deps = [name + "_p_c[toml]"])
    _py_library(name + "_q", deps = [name + "_q_c[other]"])
    analysis_test(
        name = name,
        impl = _test_different_extras_of_the_same_package_impl,
        targets = {
            "c": name + "_c",
            "p": name + "_p",
            "q": name + "_q",
        },
    )

def _test_different_extras_of_the_same_package_impl(env, targets):
    prefix = "test_different_extras_of_the_same_package_"
    env.expect.that_collection(_sources(targets.p)).contains_exactly([
        prefix + "c.py",
        prefix + "p.py",
        prefix + "tomli.py",
    ])
    env.expect.that_collection(_sources(targets.q)).contains_exactly([
        prefix + "c.py",
        prefix + "other_dep.py",
        prefix + "q.py",
    ])

    # The package without extras does not get the dependencies of the extras.
    env.expect.that_collection(_sources(targets.c)).contains_exactly([
        prefix + "c.py",
    ])

_tests.append(_test_different_extras_of_the_same_package)

def _test_env_markers_of_the_extra(name):
    # This is `coverage[toml]`, which requires
    # `tomli; python_full_version <= "3.11.0a6" and extra == "toml"`, and
    # `pytest-cov` that requires `coverage[toml]`.
    _py_library(name + "_tomli")
    rt_util.helper_target(
        env_marker_setting,
        name = name + "_include_tomli",
        expression = "python_full_version <= \"3.11.0a6\"",
    )
    _pkg(name + "_coverage", {
        "toml": select({
            ":is_{}_include_tomli_true".format(name): [name + "_tomli"],
            "//conditions:default": [],
        }),
    })
    _extra_dep(name + "_dep_coverage[toml]", name + "_coverage", "toml")
    _py_library(name + "_pytest_cov", deps = [name + "_dep_coverage[toml]"])

    for version, want in {
        "3.10": ["coverage.py", "pytest_cov.py", "tomli.py"],
        "3.12": ["coverage.py", "pytest_cov.py"],
    }.items():
        analysis_test(
            name = "{}_{}".format(name, version.replace(".", "_")),
            impl = _test_env_markers_of_the_extra_impl,
            target = name + "_pytest_cov",
            config_settings = {
                labels.PYTHON_VERSION: version,
            },
            attr_values = {
                "want": [name + "_" + w for w in want],
            },
            attrs = {
                "want": attr.string_list(),
            },
        )

    native.test_suite(
        name = name,
        tests = [
            name + "_3_10",
            name + "_3_12",
        ],
    )

def _test_env_markers_of_the_extra_impl(env, target):
    # The setting of the python version is kept when the setting of the extra
    # is set and reset.
    env.expect.that_collection(_sources(target)).contains_exactly(env.ctx.attr.want)

_tests.append(_test_env_markers_of_the_extra)

_ProvidersInfo = provider(
    doc = "The providers of a target to compare them in the tests",
    fields = ["target"],
)

def _providers_impl(ctx):
    return [_ProvidersInfo(target = ctx.attr.target)]

_providers = rule(
    implementation = _providers_impl,
    attrs = {"target": attr.label()},
)

def _test_providers_are_forwarded(name):
    _py_library(name + "_generated", data = [name + "_data.txt"])
    rt_util.helper_target(
        py_library,
        name = name + "_dep_a",
        srcs = ["instrumented.py"],
        deps = [name + "_generated"],
    )
    rt_util.helper_target(
        native.genrule,
        name = name + "_data",
        outs = [name + "_data.txt"],
        cmd = "touch $@",
    )
    _pkg(name + "_foo", {"a": [name + "_dep_a"]})
    _extra_dep(name + "_subject", name + "_foo", "a")
    rt_util.helper_target(
        _providers,
        name = name + "_want",
        target = name + "_foo[a]",
    )
    analysis_test(
        name = name,
        impl = _test_providers_are_forwarded_impl,
        targets = {
            "subject": name + "_subject",
            "want": name + "_want",
        },
        config_settings = {
            "//command_line_option:collect_code_coverage": True,
            "//command_line_option:instrumentation_filter": "//tests/pypi/extra_dep[:/]",
        },
    )

def _test_providers_are_forwarded_impl(env, targets):
    got = targets.subject
    want = targets.want[_ProvidersInfo].target

    for provider in [PyInfo, PyCcLinkParamsInfo, InstrumentedFilesInfo, OutputGroupInfo]:
        env.expect.where(provider = str(provider)).that_bool(provider in got).equals(True)

    env.expect.that_bool(got[PyInfo] == want[PyInfo]).equals(True)
    env.expect.that_bool(got[PyCcLinkParamsInfo] == want[PyCcLinkParamsInfo]).equals(True)

    # The output groups of the target.
    env.expect.that_collection(dir(got[OutputGroupInfo])).contains_exactly(dir(want[OutputGroupInfo]))
    for group in dir(want[OutputGroupInfo]):
        env.expect.where(group = group).that_depset_of_files(
            getattr(got[OutputGroupInfo], group),
        ).contains_exactly([
            f.short_path
            for f in getattr(want[OutputGroupInfo], group).to_list()
        ])

    # The files and the runfiles of the target.
    env.expect.that_depset_of_files(got[DefaultInfo].files).contains_exactly([
        f.short_path
        for f in want[DefaultInfo].files.to_list()
    ])
    for runfiles in ["default_runfiles", "data_runfiles"]:
        got_files = sorted([f.short_path for f in getattr(got[DefaultInfo], runfiles).files.to_list()])
        want_files = sorted([f.short_path for f in getattr(want[DefaultInfo], runfiles).files.to_list()])
        env.expect.where(runfiles = runfiles).that_collection(got_files).contains_exactly(want_files)
        env.expect.where(runfiles = runfiles).that_collection(got_files).contains(
            "tests/pypi/extra_dep/test_providers_are_forwarded_data.txt",
        )

    # The coverage is collected for the sources of the extra.
    got_instrumented = sorted([f.short_path for f in got[InstrumentedFilesInfo].instrumented_files.to_list()])
    env.expect.that_collection(got_instrumented).contains_exactly([
        f.short_path
        for f in want[InstrumentedFilesInfo].instrumented_files.to_list()
    ])
    env.expect.that_collection(got_instrumented).contains(
        "tests/pypi/extra_dep/instrumented.py",
    )

_tests.append(_test_providers_are_forwarded)

_VisitedInfo = provider(
    doc = "The targets visited by an aspect that propagates along the `deps`",
    fields = ["labels"],
)

def _deps_aspect_impl(target, ctx):
    return [_VisitedInfo(labels = depset(
        [target.label.name],
        transitive = [
            dep[_VisitedInfo].labels
            for dep in getattr(ctx.rule.attr, "deps", [])
            if _VisitedInfo in dep
        ],
    ))]

_deps_aspect = aspect(
    implementation = _deps_aspect_impl,
    attr_aspects = ["deps"],
)

def _with_deps_aspect_impl(ctx):
    return [ctx.attr.target[_VisitedInfo]]

_with_deps_aspect = rule(
    implementation = _with_deps_aspect_impl,
    attrs = {"target": attr.label(aspects = [_deps_aspect])},
)

def _test_aspects_propagate_along_deps(name):
    _py_library(name + "_dep_a")
    _pkg(name + "_foo", {"a": [name + "_dep_a"]})
    _extra_dep(name + "_dep_foo[a]", name + "_foo", "a")
    _py_library(name + "_consumer", deps = [name + "_dep_foo[a]"])
    rt_util.helper_target(
        _with_deps_aspect,
        name = name + "_subject",
        target = name + "_consumer",
    )
    analysis_test(
        name = name,
        impl = _test_aspects_propagate_along_deps_impl,
        target = name + "_subject",
    )

def _test_aspects_propagate_along_deps_impl(env, target):
    prefix = "test_aspects_propagate_along_deps_"
    env.expect.that_collection(target[_VisitedInfo].labels.to_list()).contains_exactly([
        prefix + "consumer",
        prefix + "dep_foo[a]",
        prefix + "foo_extras",
        prefix + "foo[a]",
        prefix + "foo",
        prefix + "dep_a",
    ])

_tests.append(_test_aspects_propagate_along_deps)

def _test_extra_select_targets(env):
    config_settings = []
    extra_selects = []

    extra_select_targets(
        name = "_extras",
        targets = {"a": ":[a]", "b": ":[b]"},
        default = ":[]",
        distribution = "foo 1.0",
        native = struct(config_setting = lambda **kwargs: config_settings.append(kwargs)),
        rules = struct(extra_select = lambda **kwargs: extra_selects.append(kwargs)),
    )

    env.expect.that_collection(config_settings).contains_exactly([
        {
            "name": "_extras_a",
            "flag_values": {str(Label("//python/private/pypi:requested_extra")): "a"},
            "visibility": ["//visibility:private"],
        },
        {
            "name": "_extras_b",
            "flag_values": {str(Label("//python/private/pypi:requested_extra")): "b"},
            "visibility": ["//visibility:private"],
        },
    ])  # buildifier: @unsorted-dict-items
    env.expect.that_collection(extra_selects).contains_exactly([
        {
            "name": "_extras",
            "deps": select({
                ":_extras_a": [":[a]"],
                ":_extras_b": [":[b]"],
                "//conditions:default": [":[]"],
            }),
            "distribution": "foo 1.0",
            "extras": ["a", "b"],
            "visibility": None,
        },
    ])  # buildifier: @unsorted-dict-items

_basic_tests.append(_test_extra_select_targets)

def _test_extra_select_targets_no_extras(env):
    extra_selects = []

    extra_select_targets(
        name = "_extras",
        targets = {},
        default = ":[]",
        native = struct(),
        rules = struct(extra_select = lambda **kwargs: extra_selects.append(kwargs)),
        visibility = ["//visibility:public"],
    )

    env.expect.that_collection(extra_selects).contains_exactly([
        {
            "name": "_extras",
            "deps": [":[]"],
            "distribution": "",
            "extras": [],
            "visibility": ["//visibility:public"],
        },
    ])  # buildifier: @unsorted-dict-items

_basic_tests.append(_test_extra_select_targets_no_extras)

def extra_dep_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(
        name = name,
        tests = _tests,
        basic_tests = _basic_tests,
    )
