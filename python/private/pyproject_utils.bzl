"""Utilities for reading Python version from pyproject.toml."""

_EXTRACTOR_SCRIPT = Label("//python/private:pyproject_version_extractor.py")

def read_pyproject_version(module_ctx, pyproject_label, logger = None):
    """Reads Python version from pyproject.toml if requested.

    Args:
        module_ctx: The module_ctx object from the module extension.
        pyproject_label: Label pointing to the pyproject.toml file, or None.
        logger: Optional logger instance for informational messages.

    Returns:
        The Python version string (e.g. "3.13.9") or None if pyproject_label is None.
    """
    if not pyproject_label:
        return None

    pyproject_path = module_ctx.path(pyproject_label)
    module_ctx.read(pyproject_path, watch = "yes")

    # Use the shared extractor script
    extractor = module_ctx.path(_EXTRACTOR_SCRIPT)
    result = module_ctx.execute([
        "python3",
        str(extractor),
        str(pyproject_path),
    ])

    if result.return_code != 0:
        fail("Failed to read Python version from pyproject.toml: " + result.stderr)

    version = result.stdout.strip()

    if logger:
        logger.info(lambda: "Read Python version {} from {}".format(version, pyproject_label))

    return version
