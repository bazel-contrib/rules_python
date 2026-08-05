"""Macro helper for py_extension build testing."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//python/cc:py_extension.bzl", "py_extension")

def py_extension_build_test(name, **kwargs):
    """Creates a py_extension target and a build_test verifying it builds."""
    py_extension(
        name = name,
        **kwargs
    )
    build_test(
        name = name + "_build_test",
        targets = [":" + name],
    )
