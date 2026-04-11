"""Mocks for testing."""

def _rctx(os_name = "linux", os_arch = "x86_64", environ = None, **kwargs):
    """Creates a mock of repository_ctx or module_ctx.

    Args:
        os_name: The OS name to mock (e.g., "linux", "Mac OS X", "windows").
        os_arch: The OS architecture to mock (e.g., "x86_64", "aarch64").
        environ: A dictionary representing the environment variables.
        **kwargs: Additional attributes to add to the mock struct.

    Returns:
        A struct mocking repository_ctx.
    """
    if environ == None:
        environ = {}

    attrs = {
        "getenv": environ.get,
        "os": struct(
            name = os_name,
            arch = os_arch,
        ),
    }
    attrs.update(kwargs)

    return struct(**attrs)

mocks = struct(
    rctx = _rctx,
)
