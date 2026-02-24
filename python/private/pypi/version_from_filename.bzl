"""Parse the version of the thing just from the filename. This is useful for selecting files based on the requested version."""

_SDIST_EXTS = [
    ".tar",  # handles any compression
    ".zip",
]

def version_from_filename(filename, _fail = None):
    """Parse the version of the filename.

    Args:
        filename: {type}`str` the filename.
        _fail: The fail function.

    Returns:
        A string version or None if we could not parse the version.
    """
    # See https://packaging.python.org/en/latest/specifications/binary-distribution-format/#binary-distribution-format

    if filename.endswith(".whl"):
        # The format is {name}-{version}-{whl_specifiers}.whl
        _, _, version = filename.partition("-")
        version, _, _ = version.partition("-")
        return version

    # NOTE @aignas 2025-03-29: most of the files are wheels, so this is not the common path

    # {name}-{version}.{ext}
    head = ""
    for ext in _SDIST_EXTS:
        head, _, _ = filename.rpartition(ext)  # build or name
        if head:
            break

    if not head:
        if _fail:
            _fail("Unsupported sdist extension: {filename}".format(filename = filename))
        return None

    # Based on PEP440 the version number cannot include dashes
    _, _, version = head.rpartition("-")
    return version
