"A simple utility function to get the python_tag from the implementation name"

# Taken from
# https://packaging.python.org/en/latest/specifications/platform-compatibility-tags/#python-tag
_PY_TAGS = {
    # "py": Generic Python (does not require implementation-specific features)
    "cpython": "cp",
    "ironpython": "ip",
    "jython": "jy",
    "pypy": "pp",
    "python": "py",
}
PY_TAG_GENERIC = "py"

def python_tag(implementation_name, python_version = ""):
    """Get the python_tag from the implementation_name.

    Args:
        implementation_name: {type}`str` the implementation name, e.g. "cpython"
        python_version: {type}`str` the Python version, e.g. `3.14` or
            `3.14.1`.

    Returns:
        A {type}`str` that represents the python_tag with a version if the
            python_version is given.
    """
    if python_version:
        major, minor = python_major_minor(python_version)
        suffix = "{}{}".format(major, "" if minor == None else minor)
    else:
        suffix = ""

    return "{}{}".format(
        _PY_TAGS.get(implementation_name, implementation_name),
        suffix,
    )

def python_major_minor(python_version):
    """Get the major and maybe minor numbers of a Python version.

    Only the first two numbers of the version are needed to match the
    wheel tags, so the version is not parsed as per PEP 440.

    Args:
        python_version: {type}`str` the Python version, e.g. `3.14`,
            `3.14.1` or `3.15.0rc1`.

    Returns:
        A {type}`tuple[int, int | None]` of the major and minor numbers, the
        minor is `None` if the version does not have it.
    """
    major, _, tail = python_version.partition(".")
    tail, _, _ = tail.partition(".")

    # Drop what may follow the minor number, e.g. `rc1` in `3.15rc1`
    minor = ""
    for c in tail.elems():
        if not c.isdigit():
            break
        minor += c

    if not major.isdigit() or (tail and not minor):
        fail("Expected the Python version to start with '<major>.<minor>', got: '{}'".format(python_version))

    return (int(major), int(minor) if minor else None)
