"""A rule exposing the uv binary from the registered toolchain as an executable target.

This allows running ``bazel run //:uv -- <args>`` from the test workspace.
"""

def _uv_runner_impl(ctx):
    toolchain_info = ctx.toolchains["@rules_python//python/uv:uv_toolchain_type"]
    original_uv_executable = toolchain_info.uv_toolchain_info.uv[DefaultInfo].files_to_run.executable

    ext = ""
    if ctx.attr.is_windows:
        ext = ".exe"

    uv_exe = ctx.actions.declare_file("uv" + ext)
    ctx.actions.symlink(output = uv_exe, target_file = original_uv_executable)

    return DefaultInfo(
        files = depset([uv_exe]),
        executable = uv_exe,
        runfiles = toolchain_info.default_info.default_runfiles,
    )

uv_runner = rule(
    implementation = _uv_runner_impl,
    executable = True,
    attrs = {
        "is_windows": attr.bool(mandatory = True),
    },
    toolchains = ["@rules_python//python/uv:uv_toolchain_type"],
)
