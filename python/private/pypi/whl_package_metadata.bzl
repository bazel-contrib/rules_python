"""The package metadata for the whl repositories.

This is loaded only by the generated `BUILD.bazel` files of the whl
repositories, so that the `@package_metadata` repository is not needed when
loading the repository rules, e.g. in `WORKSPACE`.
"""

load("@package_metadata//purl:purl.bzl", "purl")
load("@package_metadata//rules:package_metadata.bzl", "package_metadata")

def whl_package_metadata(*, distribution, version, repository_url = None, file_name = None):
    """Create the `package_metadata` target with a PyPI PURL.

    See https://github.com/package-url/purl-spec/blob/main/types-doc/pypi-definition.md

    Args:
        distribution: {type}`str` the normalized name of the distribution.
        version: {type}`str` the version of the package.
        repository_url: {type}`str | None` the index URL.
        file_name: {type}`str | None` the name of the whl or sdist file.
    """
    builder = purl.builder().type("pypi").name(distribution).version(version)
    if repository_url:
        builder.add_qualifier("repository_url", repository_url)
    if file_name:
        builder.add_qualifier("file_name", file_name)

    package_metadata(
        name = "package_metadata",
        purl = builder.build(),
        visibility = ["//:__subpackages__"],
    )
