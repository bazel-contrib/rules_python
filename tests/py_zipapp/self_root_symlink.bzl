"""A rule whose runfiles root symlink is at its target file's own path."""

def _self_root_symlink_impl(ctx):
    f = ctx.file.src
    return [DefaultInfo(runfiles = ctx.runfiles(
        files = [f],
        root_symlinks = {ctx.workspace_name + "/" + f.short_path: f},
    ))]

self_root_symlink = rule(
    implementation = _self_root_symlink_impl,
    attrs = {
        "src": attr.label(allow_single_file = True, mandatory = True),
    },
)
