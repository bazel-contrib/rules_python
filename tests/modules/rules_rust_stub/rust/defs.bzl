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

def _noop_aspect_impl(_target, _ctx):
    return []

# The root .bazelrc applies these aspects on every build (see the `rust-lint`
# config). They do nothing here because the stub has no Rust targets to lint.
rust_clippy_aspect = aspect(implementation = _noop_aspect_impl)
rustfmt_aspect = aspect(implementation = _noop_aspect_impl)
