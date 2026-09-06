"""Stub implementation of rules_rust for WORKSPACE mode."""

# buildifier: disable=unused-variable
def rust_library(name, **_kwargs):
    """Stub rust_library rule for WORKSPACE mode.

    Args:
        name: Target name.
        **_kwargs: Ignored keyword arguments.
    """
    native.filegroup(
        name = name,
        tags = ["manual"],
    )

# buildifier: disable=unused-variable
def rust_binary(name, **_kwargs):
    """Stub rust_binary rule for WORKSPACE mode.

    Args:
        name: Target name.
        **_kwargs: Ignored keyword arguments.
    """
    native.filegroup(
        name = name,
        tags = ["manual"],
    )

# buildifier: disable=unused-variable
def rust_test(name, **_kwargs):
    """Stub rust_test rule for WORKSPACE mode.

    Args:
        name: Target name.
        **_kwargs: Ignored keyword arguments.
    """
    native.filegroup(
        name = name,
        tags = ["manual"],
    )
