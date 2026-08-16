"""Public entry point for SphinxDocsLibraryInfo.

Lets custom rules supply doc files to `sphinx_docs` without depending on the
`sphinx_docs_library` rule implementation:

```starlark
load(
    "@sphinxdocs//sphinxdocs:sphinx_docs_library_info.bzl",
    "create_sphinx_docs_library_info",
)

def _my_docs_impl(ctx):
    return [create_sphinx_docs_library_info(
        files = ctx.files.srcs,
        prefix = "my_docs/",
        strip_prefix = ctx.label.package + "/",
        deps = ctx.attr.deps,
    )]
```
"""

load(
    "//sphinxdocs/private:sphinx_docs_library_info.bzl",
    _SphinxDocsFileset = "SphinxDocsFileset",
    _SphinxDocsLibraryInfo = "SphinxDocsLibraryInfo",
    _create_sphinx_docs_library_info = "create_sphinx_docs_library_info",
)

# buildifier: disable=name-conventions
SphinxDocsFileset = _SphinxDocsFileset

SphinxDocsLibraryInfo = _SphinxDocsLibraryInfo

create_sphinx_docs_library_info = _create_sphinx_docs_library_info
