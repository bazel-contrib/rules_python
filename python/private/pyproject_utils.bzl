"""Utilities for reading values from pyproject.toml."""

load("@pypackaging.bzl", "pypackaging")
load("@toml.bzl", "toml")

def read_pyproject(module_ctx, pyproject):
    """Read a pyproject.toml file and return the relevant fields.

    The file is parsed with a pure-Starlark TOML decoder; no Python
    interpreter is required. The raw `requires-python` value is returned
    as-is so that callers can decide how to interpret it.

    Args:
        module_ctx: the module extension context (needs `path` and `read`).
        pyproject: {type}`Label` pointing at the pyproject.toml file.

    Returns:
        {type}`struct` with the attributes:
          * `requires_python`: {type}`str | None` the raw `requires-python`
            value (e.g. `"==3.13.9"`), or `None` if it is not set.
    """
    data = toml.decode(module_ctx.read(module_ctx.path(pyproject), watch = "yes"))
    return struct(
        requires_python = data.get("project", {}).get("requires-python"),
    )

def version_from_requires_python(requires_python):
    """Derive a concrete Python version from a `requires-python` value.

    Currently only an exact `==X.Y.Z` specifier is supported. The value is
    validated and normalized via `pypackaging.bzl` so that malformed input
    fails in a consistent way. Broader specifier support (e.g. `>=`, `X.Y`)
    can be layered on here in the future.

    Args:
        requires_python: {type}`str` the raw `requires-python` value.

    Returns:
        {type}`str` the normalized version string (e.g. `"3.13.9"`).
    """
    if not requires_python:
        fail("`requires-python` must be specified")

    specs = pypackaging.specifiers.parse_set(requires_python).specs
    if len(specs) != 1 or specs[0].operator != "==" or specs[0].version.endswith(".*"):
        fail("`requires-python` must pin an exact version with `==`, got: {}".format(requires_python))

    return pypackaging.version.to_string(specs[0].parsed_version)
