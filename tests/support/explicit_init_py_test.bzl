"""Parameterized analysis test for __init__.py generation behavior."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", rt_util = "util")
load("//python:py_binary.bzl", "py_binary")
load("//python/private:bzlmod_enabled.bzl", "BZLMOD_ENABLED")  # buildifier: disable=bzl-visibility

def _explicit_init_py_test_impl(env, target):
    empty_filenames = target[DefaultInfo].default_runfiles.empty_filenames.to_list()
    collection = env.expect.that_collection(
        empty_filenames,
        container_name = "empty_filenames",
    )
    if env.ctx.attr.expect_generated_init:
        collection.contains_predicate(matching.str_endswith("__init__.py"))
    else:
        collection.not_contains_predicate(matching.str_endswith("__init__.py"))

def explicit_init_py_test(*, name, main, expect_generated_init, legacy_create_init = -1, **kwargs):
    """Test that verifies whether __init__.py is generated for a py_binary.

    Args:
        name: Test name.
        main: Source file for the py_binary subject.
        expect_generated_init: Whether __init__.py generation is expected.
        legacy_create_init: Value for the legacy_create_init attribute (-1, 0, or 1).
        **kwargs: Additional args forwarded to the test rule (e.g. tags).
    """
    if not BZLMOD_ENABLED:
        native.test_suite(name = name, tests = [])
        return

    subject_name = name + "_subject"
    rt_util.helper_target(
        py_binary,
        name = subject_name,
        srcs = [main],
        main = main,
        legacy_create_init = legacy_create_init,
    )
    analysis_test(
        name = name,
        target = subject_name,
        impl = _explicit_init_py_test_impl,
        attrs = {
            "expect_generated_init": attr.bool(mandatory = True),
        },
        attr_values = dict(kwargs, expect_generated_init = expect_generated_init),
    )
