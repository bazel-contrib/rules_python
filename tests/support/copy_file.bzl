"""Copies a file to a directory."""

def _copy_file_to_dir_impl(ctx):
    out_file = ctx.actions.declare_file(
        "{}/{}".format(ctx.attr.out_dir, ctx.file.src.basename),
    )
    ctx.actions.run_shell(
        inputs = [ctx.file.src],
        outputs = [out_file],
        arguments = [ctx.file.src.path, out_file.path],
        command = 'cp -f "$1" "$2"',
        progress_message = "Copying %{input} to %{output}",
    )
    return [DefaultInfo(files = depset([out_file]))]

copy_file_to_dir = rule(
    implementation = _copy_file_to_dir_impl,
    attrs = {
        "out_dir": attr.string(mandatory = True),
        "src": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
    },
)
