"""Utilities for reading Python version from pyproject.toml."""

_TOML2JSON = Label("//tools/private/toml2json:toml2json.py")

def _parse_requires_python(requires_python):
    """Parse and validate the requires-python field.

    Args:
        requires_python: The raw requires-python string from pyproject.toml.

    Returns:
        The bare version string (e.g. "3.13.9").
    """
    if not requires_python.startswith("=="):
        fail("requires-python must use '==' for exact version, got: {}".format(requires_python))

    bare_version = requires_python[2:].strip()

    # Validate X.Y.Z format
    parts = bare_version.split(".")
    if len(parts) != 3:
        fail("requires-python must be in X.Y.Z format, got: {}".format(bare_version))
    for part in parts:
        if not part.isdigit():
            fail("requires-python must be in X.Y.Z format, got: {}".format(bare_version))

    return bare_version

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

    toml2json = module_ctx.path(_TOML2JSON)
    result = module_ctx.execute([
        "python3",
        str(toml2json),
        str(pyproject_path),
    ])

    if result.return_code != 0:
        fail("Failed to parse pyproject.toml: " + result.stderr)

    data = json.decode(result.stdout)
    requires_python = data.get("project", {}).get("requires-python")
    if not requires_python:
        fail("pyproject.toml must contain [project] requires-python field")

    version = _parse_requires_python(requires_python)

    if logger:
        logger.info(lambda: "Read Python version {} from {}".format(version, pyproject_label))

    return version
