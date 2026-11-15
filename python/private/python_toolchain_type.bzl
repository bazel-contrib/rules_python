"""Helper macro for defining the Python toolchain type target."""

load("@rules_python_internal//:rules_python_config.bzl", "config")

def python_toolchain_type(name, **kwargs):
    """Defines the Python toolchain type target or aliases `@bazel_tools`.

    Bazel versions that forward `@bazel_tools//tools/python:toolchain_type` to
    this target get the actual `toolchain_type`. On all others, this is an alias
    of the type in `@bazel_tools`, so that both labels always refer to the same
    type.

    Args:
        name: {type}`str` The name of the target.
        **kwargs: Additional attributes forwarded to `toolchain_type` or
            `alias`.
    """
    if config.toolchain_type_in_rules_python:
        native.toolchain_type(
            name = name,
            **kwargs
        )
    else:
        native.alias(
            name = name,
            actual = "@bazel_tools//tools/python:toolchain_type",
            **kwargs
        )
