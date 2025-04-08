def _generate_repl_main_impl(ctx):
    args = ctx.actions.args()
    args.add_all([
        ctx.file._template,
        ctx.file.src,
        ctx.outputs.out,
    ])

    ctx.actions.run(
        executable = ctx.executable._generator,
        inputs = [
            ctx.file._template,
            ctx.file.src,
        ],
        outputs = [ctx.outputs.out],
        arguments = [args],
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
        "_template": attr.label(
            default = "//python/private:repl_template.py",
            allow_single_file = True,
        ),
        "_generator": attr.label(
            default = "//python/private:repl_main_generator",
            executable = True,
            cfg = "exec",
        ),
    },
)
