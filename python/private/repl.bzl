def _generate_repl_main_impl(ctx):
    stub_repo = ctx.attr.src.label.repo_name or ctx.workspace_name
    stub_path = "/".join([stub_repo, ctx.file.src.short_path])

    ctx.actions.expand_template(
        template = ctx.file._template,
        output = ctx.outputs.out,
        substitutions = {
            "%stub_path%": stub_path,
        },
    )

generate_repl_main = rule(
    implementation = _generate_repl_main_impl,
    attrs = {
        "out": attr.output(
            mandatory = True,
        ),
        "src": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "_generator": attr.label(
            default = "//python/private:repl_main_generator",
            executable = True,
            cfg = "exec",
        ),
        "_template": attr.label(
            default = "//python/private:repl_template.py",
            allow_single_file = True,
        ),
    },
)
