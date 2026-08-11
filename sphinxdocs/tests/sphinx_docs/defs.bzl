"""Supporting code for tests."""

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
