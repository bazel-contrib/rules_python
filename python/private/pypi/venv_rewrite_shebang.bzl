"""Rule for rewriting portable shebangs."""

load("//python/private:attributes.bzl", "WINDOWS_CONSTRAINTS_ATTRS")
load("//python/private:common.bzl", "is_windows_platform", "runfiles_root_path")
load("//python/private:py_info.bzl", "PyInfoBuilder", "VenvSymlinkEntry", "VenvSymlinkKind")
load("//python/private:rule_builders.bzl", "ruleb")

def _venv_rewrite_shebang_impl(ctx):
    is_windows = is_windows_platform(ctx)

    out_name = ctx.label.name
    if is_windows:
        out_name += ".bat"

    out_file = ctx.actions.declare_file(out_name)
    in_file = ctx.file.src

    action_args = ctx.actions.args()
    rewriter_file = ctx.files._venv_shebang_rewriter[0]
    inputs = depset([in_file, rewriter_file])

    if rewriter_file.path.endswith(".ps1"):
        action_exe = "powershell.exe"
        action_args.add_all([
            "-ExecutionPolicy",
            "Bypass",
            "-NoProfile",
            "-File",
            rewriter_file,
        ])
    else:
        action_exe = ctx.attr._venv_shebang_rewriter[DefaultInfo].files_to_run

    action_args.add(in_file)
    action_args.add(out_file)
    action_args.add("windows" if is_windows else "unix")

    ctx.actions.run(
        inputs = inputs,
        outputs = [out_file],
        executable = action_exe,
        arguments = [action_args],
        mnemonic = "PyVenvRewriteBin",
        progress_message = "Rewriting venv bin script %{input}",
        toolchain = None,
    )

    symlink = VenvSymlinkEntry(
        kind = VenvSymlinkKind.BIN,
        link_to_path = runfiles_root_path(ctx, out_file.short_path),
        link_to_file = out_file,
        venv_path = out_name,
        package = ctx.attr.package,
        version = ctx.attr.version,
        files = depset([out_file]),
    )
    builder = PyInfoBuilder.new()
    builder.venv_symlinks.add([symlink])
    py_info = builder.build()

    return [
        DefaultInfo(files = depset([out_file]), executable = out_file),
        py_info,
    ]

_builder = ruleb.Rule(
    implementation = _venv_rewrite_shebang_impl,
    executable = True,
)
_builder.attrs.update({
    "package": attr.string(),
    "src": attr.label(mandatory = True, allow_single_file = True),
    "version": attr.string(),
    "_venv_shebang_rewriter": attr.label(
        default = "//python/private/pypi:venv_shebang_rewriter",
        allow_files = True,
        cfg = "exec",
    ),
})
_builder.attrs.update(WINDOWS_CONSTRAINTS_ATTRS)

venv_rewrite_shebang = _builder.build()
