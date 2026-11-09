"""The archive extraction features of the running Bazel version.

This only uses `native.bazel_version`, so that the repository rules can use it
without loading the `@rules_python_internal` repository, which may not be
defined yet when the WORKSPACE macros are loaded.
"""

def _major_minor(bazel_version):
    # An empty version signifies a development build, which is treated as
    # the latest version.
    if not bazel_version:
        return 99999, 99999

    parts = bazel_version.split(".")
    return int(parts[0]), int(parts[1])

def extract_features(bazel_version = None):
    """Return the archive extraction features of the Bazel version.

    Args:
        bazel_version: {type}`str | None` the Bazel version, defaults to
            `native.bazel_version`.

    Returns:
        {type}`struct` with:
        * `supports_whl_extraction`: {type}`bool` whether `.whl` files can
          be extracted, which requires Bazel 8.3.0 or later.
        * `extract_needs_chmod`: {type}`bool` whether the extracted files need
          their permissions fixed, which is the case before Bazel 8.6.0.
    """
    if bazel_version == None:
        bazel_version = native.bazel_version

    major, minor = _major_minor(bazel_version)
    return struct(
        supports_whl_extraction = major > 8 or (major == 8 and minor >= 3),
        extract_needs_chmod = major < 8 or (major == 8 and minor < 6),
    )
