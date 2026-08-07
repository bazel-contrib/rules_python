"""Stub implementation of rules_pyrefly for WORKSPACE mode."""

# buildifier: disable=unused-variable
def _noop_aspect_impl(_target, _ctx):
    return []

_noop_aspect = aspect(
    implementation = _noop_aspect_impl,
    doc = "No-op Pyrefly aspect stub for WORKSPACE mode.",
)

def pyrefly(**_kwargs):
    """Stub pyrefly aspect constructor.

    Args:
        **_kwargs: Ignored keyword arguments.

    Returns:
        A no-op aspect.
    """
    return _noop_aspect
