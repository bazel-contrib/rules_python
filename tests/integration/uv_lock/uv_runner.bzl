"""A rule exposing the uv binary from the registered toolchain as an executable target.

This allows running ``bazel run //:uv -- <args>`` from the test workspace.
"""

def _uv_runner_impl(ctx):
    toolchain_info = ctx.toolchains["@rules_python//python/uv:uv_toolchain_type"]
    original_uv_executable = toolchain_info.uv_toolchain_info.uv[DefaultInfo].files_to_run.executable

    uv_symlink = ctx.actions.declare_file("uv")
    ctx.actions.symlink(output = uv_symlink, target_file = original_uv_executable)

    return DefaultInfo(
        files = depset([uv_symlink]),
        executable = uv_symlink,
        runfiles = toolchain_info.default_info.default_runfiles,
    )

uv_runner = rule(
    implementation = _uv_runner_impl,
    executable = True,
    toolchains = ["@rules_python//python/uv:uv_toolchain_type"],
)
