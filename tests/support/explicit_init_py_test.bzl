"""Parameterized analysis test for __init__.py generation behavior."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//python:py_binary.bzl", "py_binary")
load("//python/private:bzlmod_enabled.bzl", "BZLMOD_ENABLED")  # buildifier: disable=bzl-visibility

def _explicit_init_py_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    empty_filenames = target[DefaultInfo].default_runfiles.empty_filenames.to_list()
    init_pys = [f for f in empty_filenames if f.endswith("__init__.py")]

    if ctx.attr.expect_generated_init:
        asserts.true(env, len(init_pys) > 0, "Expected __init__.py to be generated")
    else:
        asserts.true(env, len(init_pys) == 0, "Expected __init__.py to NOT be generated")

    return analysistest.end(env)

_explicit_init_py_test = analysistest.make(
    _explicit_init_py_test_impl,
    attrs = {
        "expect_generated_init": attr.bool(mandatory = True),
    },
)

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
    py_binary(
        name = subject_name,
        srcs = [main],
        main = main,
        legacy_create_init = legacy_create_init,
        tags = kwargs.pop("tags", ["manual"]),
        **kwargs
    )
    _explicit_init_py_test(
        name = name,
        target_under_test = subject_name,
        expect_generated_init = expect_generated_init,
        **kwargs
    )
