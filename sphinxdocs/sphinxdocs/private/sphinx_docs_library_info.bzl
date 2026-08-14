"""Provider for collecting doc files as libraries."""
SphinxDocsFileset = provider(
    doc = "A set of doc files sharing the same path manipulation.",
    fields = {
        "files": """
:type: tuple[File]

The documentation files. A tuple because depset elements must be immutable.
""",
        "prefix": """
:type: str

Prefix to prepend to file paths in `files`. Added after `strip_prefix` is removed.
""",
        "strip_prefix": """
:type: str

Prefix to remove from file paths in `files`. Removed before `prefix` is prepended.
""",
    },
)

SphinxDocsLibraryInfo = provider(
    doc = "Information about a collection of doc files.",
    fields = {
        "files": """
:type: list[File]

The direct documentation files for the library.
""",
        "prefix": """
:type: str

Prefix to prepend to file paths in `files`. Added after `strip_prefix` is removed.
""",
        "strip_prefix": """
:type: str

Prefix to remove from file paths in `files`. Removed before `prefix` is prepended.
""",
        "transitive": """
:type: depset[SphinxDocsFileset]

This library's own files and those of its deps.

The only field consumers read, so a rule must include its own
{obj}`SphinxDocsFileset` here or its files are silently ignored. Use
{obj}`create_sphinx_docs_library_info` to construct the provider correctly.
""",
    },
)

def create_sphinx_docs_library_info(*, files = [], prefix = "", strip_prefix = "", deps = []):
    """Creates a {obj}`SphinxDocsLibraryInfo`, populating the `transitive` field.

    Args:
        files: {type}`list[File]` the direct doc files.
        prefix: {type}`str` prefix to prepend to `files` paths. Not applied to `deps`.
        strip_prefix: {type}`str` prefix to remove from `files` paths. Not applied to `deps`.
        deps: {type}`list[Target]` targets with {obj}`SphinxDocsLibraryInfo` whose
            files are included as-is.

    Returns:
        {type}`SphinxDocsLibraryInfo`
    """
    direct = []
    if files:
        direct.append(SphinxDocsFileset(
            files = tuple(files),
            prefix = prefix,
            strip_prefix = strip_prefix,
        ))

    return SphinxDocsLibraryInfo(
        files = files,
        prefix = prefix,
        strip_prefix = strip_prefix,
        transitive = depset(
            direct = direct,
            transitive = [d[SphinxDocsLibraryInfo].transitive for d in deps],
        ),
    )
