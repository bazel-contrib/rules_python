"A simple utility function to get the python_tag from the implementation name"

# Taken from
# https://packaging.python.org/en/latest/specifications/platform-compatibility-tags/#python-tag
_PY_TAGS = {
    # "py": Generic Python (does not require implementation-specific features)
    "cpython": "cp",
    "ironpython": "ip",
    "jython": "jy",
    "pypy": "pp",
}
PY_TAG_GENERIC = "py"

def python_tag(implementation_name):
    """Get the python_tag from the implementation_name.

    Args:
        implementation_name: {type}`str` the implementation name, e.g. "cpython"

    Returns:
        A {type}`str` that represents the python_tag.
    """
    return _PY_TAGS.get(implementation_name, implementation_name)
