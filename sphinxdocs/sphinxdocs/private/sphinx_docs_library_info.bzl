"""Provider for collecting doc files as libraries."""

# NOTE: A provider is used for memory efficiency because providers perform key
# sharing.
# buildifier: disable=name-conventions
SphinxDocsFileset = provider(
    doc = "A set of doc files sharing the same path manipulation.",
    fields = {
        "files": """
:type: tuple[File]

The documentation files. A tuple because depset elements must be immutable.
""",
        "prefix": """
:type: str

Prefix to prepend to file paths in `files`. Added after `strip_prefix` is
removed.
""",
        "strip_prefix": """
:type: str

Prefix to remove from file paths in `files`. Removed before `prefix` is
prepended.
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

Prefix to prepend to file paths in `files`. Added after `strip_prefix` is
removed.
""",
        "strip_prefix": """
:type: str

Prefix to remove from file paths in `files`. Removed before `prefix` is
prepended.
""",
        "transitive": """
:type: depset[SphinxDocsFileset]

This library's own files and those of its deps.

A rule must include its own {obj}`SphinxDocsFileset` here or its files won't be
propagated (and thus silently dropped). Use
{obj}`create_sphinx_docs_library_info` to construct the provider correctly.
""",
    },
)

def create_sphinx_docs_library_info(
        *,
        files = [],
        prefix = "",
        strip_prefix = "",
        deps = [],
        transitives = []):
    """Creates a {obj}`SphinxDocsLibraryInfo`, populating the `transitive` field.

    Args:
        files: {type}`list[File]` the direct doc files.
        prefix: {type}`str` prefix to prepend to `files` paths. Not applied to
            `deps`.
        strip_prefix: {type}`str` prefix to remove from `files` paths. Not
            applied to `deps`.
        deps: {type}`list[Target]` targets whose {obj}`SphinxDocsLibraryInfo`
            files are added as transitive (not direct) files. It is not
            required that targets have the provider; targets without it are
            ignored.
        transitives: {type}`list[SphinxDocsFileset] | depset[SphinxDocsFileset]`
            {obj}`SphinxDocsFileset` objects whose files are added as
            transitive (not direct) files.

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

    transitive_depsets = [
        d[SphinxDocsLibraryInfo].transitive
        for d in deps
        if SphinxDocsLibraryInfo in d
    ]
    if transitives:
        if type(transitives) == "depset":
            transitive_depsets.append(transitives)
        else:
            direct.extend(transitives)

    return SphinxDocsLibraryInfo(
        files = files,
        prefix = prefix,
        strip_prefix = strip_prefix,
        transitive = depset(
            direct = direct,
            transitive = transitive_depsets,
        ),
    )
