"""Tests for the extra_dep and extra_select rules."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_info.bzl", "PyInfo")
load("//python:py_library.bzl", "py_library")
load("//python/private/pypi:extra_dep.bzl", "extra_dep", "extra_select_targets")  # buildifier: disable=bzl-visibility

_tests = []
_basic_tests = []

def _py_library(name):
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
    )

def _setup(name):
    """Create the targets of a package `foo` that provides the `a` extra."""
    _py_library(name + "_foo")
    _py_library(name + "_dep_a")
    rt_util.helper_target(
        py_library,
        name = name + "_foo[a]",
        deps = [name + "_foo", name + "_dep_a"],
    )
    extra_select_targets(
        name = name + "_extras",
        targets = {"a": name + "_foo[a]"},
        default = name + "_foo",
        visibility = ["//visibility:private"],
    )

def _sources(target):
    return [f.basename for f in target[PyInfo].transitive_sources.to_list()]

def _test_extra(name):
    _setup(name)
    rt_util.helper_target(
        extra_dep,
        name = name + "_subject",
        pkg = name + "_extras",
        extra = "a",
    )
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
    _setup(name)
    rt_util.helper_target(
        extra_dep,
        name = name + "_subject",
        pkg = name + "_extras",
        extra = "unknown",
    )
    analysis_test(
        name = name,
        impl = _test_unknown_extra_impl,
        target = name + "_subject",
    )

def _test_unknown_extra_impl(env, target):
    # Like `pip`, the extras that the package does not provide are ignored.
    env.expect.that_collection(_sources(target)).contains_exactly([
        "test_unknown_extra_foo.py",
    ])

_tests.append(_test_unknown_extra)

def _test_extra_select_targets(env):
    config_settings = []
    extra_selects = []

    extra_select_targets(
        name = "_extras",
        targets = {"a": ":[a]", "b": ":[b]"},
        default = ":pkg",
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
            "actual": select({
                ":_extras_a": ":[a]",
                ":_extras_b": ":[b]",
                "//conditions:default": ":pkg",
            }),
            "visibility": None,
        },
    ])  # buildifier: @unsorted-dict-items

_basic_tests.append(_test_extra_select_targets)

def _test_extra_select_targets_no_extras(env):
    extra_selects = []

    extra_select_targets(
        name = "_extras",
        targets = {},
        default = ":pkg",
        native = struct(),
        rules = struct(extra_select = lambda **kwargs: extra_selects.append(kwargs)),
        visibility = ["//visibility:public"],
    )

    env.expect.that_collection(extra_selects).contains_exactly([
        {
            "name": "_extras",
            "actual": ":pkg",
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
