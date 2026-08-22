"""Supporting code for tests."""

load(
    "//sphinxdocs:sphinx_docs_library_info.bzl",
    "SphinxDocsFileset",
    "SphinxDocsLibraryInfo",
    "create_sphinx_docs_library_info",
)

def _custom_docs_library_impl(ctx):
    files = []
    if ctx.attr.page_name:
        out = ctx.actions.declare_file(ctx.attr.page_name + ".md")
        ctx.actions.write(out, "# {}\n".format(ctx.attr.page_name))
        files.append(out)

    transitives = []
    for d in ctx.attr.transitive_deps:
        if SphinxDocsLibraryInfo in d:
            transitives.append(d[SphinxDocsLibraryInfo].transitive)

    info = create_sphinx_docs_library_info(
        files = files,
        prefix = ctx.attr.prefix,
        strip_prefix = ctx.label.package + "/",
        deps = ctx.attr.deps,
        transitives = transitives[0] if len(transitives) == 1 else transitives,
    )
    if type(info.files) != "list":
        fail("Expected SphinxDocsLibraryInfo.files to be a list, got: {}".format(
            type(info.files),
        ))

    # Also test passing a list of SphinxDocsFileset objects to transitives:
    test_fileset_info = create_sphinx_docs_library_info(
        transitives = [
            SphinxDocsFileset(
                files = tuple(files),
                prefix = "fileset/",
                strip_prefix = "",
            ),
        ],
    )
    if type(test_fileset_info.files) != "list":
        fail("Expected SphinxDocsLibraryInfo.files to be a list, got: {}".format(
            type(test_fileset_info.files),
        ))
    if test_fileset_info.transitive.to_list():
        first_fileset = test_fileset_info.transitive.to_list()[0]
        if type(first_fileset.files) != "tuple":
            fail("Expected SphinxDocsFileset.files to be a tuple, got: {}".format(
                type(first_fileset.files),
            ))

    return [
        info,
        DefaultInfo(files = depset(files)),
    ]

# Verifies a rule that isn't sphinx_docs_library can supply doc files to
# sphinx_docs using only the public SphinxDocsLibraryInfo entry point.
custom_docs_library = rule(
    implementation = _custom_docs_library_impl,
    attrs = {
        "deps": attr.label_list(),
        # When unset, the rule produces no direct files, which exercises the
        # empty-files path of create_sphinx_docs_library_info.
        "page_name": attr.string(),
        "prefix": attr.string(),
        "transitive_deps": attr.label_list(),
    },
)

def _gen_directory_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name)

    ctx.actions.run_shell(
        outputs = [out],
        command = """
printf '# Hello\\n' > {outdir}/index.md
printf '# Dir Page 1\\n\\n[Dir Page 2](dir_page2.md)\\n' > {outdir}/dir_page1.md
printf '# Dir Page 2\\n' > {outdir}/dir_page2.md
""".format(
            outdir = out.path,
        ),
    )

    return [DefaultInfo(files = depset([out]))]

gen_directory = rule(
    implementation = _gen_directory_impl,
)
