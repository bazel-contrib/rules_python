"""Toolchain for the unified Rust shrubbery binary."""

load("//python/private:sentinel_impl.bzl", "SentinelInfo")
load("//python/private:toolchain_types.bzl", "SHRUBBERY_TOOLCHAIN_TYPE")

def _shrubbery_toolchain_impl(ctx):
    shrubbery = ctx.attr.shrubbery
    if shrubbery != None and SentinelInfo in shrubbery:
        shrubbery = None

    return [
        platform_common.ToolchainInfo(
            shrubbery = shrubbery,
        ),
    ]

shrubbery_toolchain = rule(
    implementation = _shrubbery_toolchain_impl,
    doc = """
Provides the unified `shrubbery` ("Shell replacements for Bazel build tools in
Rust") subcommand binary.

This provides `ToolchainInfo` with the following attributes:
* `shrubbery`: {type}`Target | None`. Invoked as
  `<binary> <subcommand> [args...]`. Must provide `DefaultInfo.files_to_run`.
  If `None`, the rules fall back to their built-in Python or script
  implementations.
""",
    attrs = {
        "shrubbery": attr.label(
            # NOTE: This is an executable, but can't use `executable = True`
            # because the `//python:none` sentinel isn't executable.
            # `allow_files = True` (not `allow_single_file`) because binary
            # targets can have multiple files in `DefaultInfo.files`.
            allow_files = True,
            cfg = "exec",
            doc = """
The unified `shrubbery` binary.

To indicate no tool, specify the special target {obj}`//python:none`.
""",
        ),
    },
)

def get_shrubbery_tool(ctx, subcommand, fallback):
    """Returns how to run a rules_python build tool subcommand or its fallback.

    Prefers the `shrubbery` binary from the `shrubbery` toolchain, if one is
    resolved and provides it, prepending `subcommand` to its arguments.
    Otherwise, falls back to `fallback`.

    Args:
        ctx: The rule context. The rule must declare
            `SHRUBBERY_TOOLCHAIN_TYPE` as an optional toolchain.
        subcommand: {type}`str` Subcommand name passed as `argv[1]` when running
            `shrubbery`.
        fallback: {type}`Target` Fallback tool target when no `shrubbery`
            toolchain is resolved.

    Returns:
        {type}`struct` with fields:
        * `executable`: {type}`Target` to pass to `actions_run()`.
        * `files_to_run`: {type}`FilesToRunProvider` to pass to
          `ctx.actions.run(executable = ...)`.
        * `is_rust`: {type}`bool` True when resolved from the `shrubbery`
          toolchain.
        * `prefix_args`: {type}`list[str]` `[subcommand]` when `is_rust` is
          True, else `[]`.
        * `toolchain`: {type}`Label | None` the toolchain type to pass to
          `actions_run()` or `ctx.actions.run()` so the action runs on the exec
          platform the tool was built for. `None` when falling back to
          `fallback`.
    """
    toolchain = ctx.toolchains[SHRUBBERY_TOOLCHAIN_TYPE]
    if toolchain and toolchain.shrubbery:
        executable = toolchain.shrubbery
        return struct(
            # Target to pass to `actions_run()`.
            executable = executable,
            # `FilesToRunProvider` to pass to `ctx.actions.run(executable = ...)`.
            files_to_run = executable[DefaultInfo].files_to_run,
            # True when resolved from the `shrubbery` toolchain.
            is_rust = True,
            # Leading subcommand argument prepended when invoking `shrubbery`.
            prefix_args = [subcommand],
            # Toolchain type for `actions_run()` / `ctx.actions.run()`.
            toolchain = SHRUBBERY_TOOLCHAIN_TYPE,
        )
    return struct(
        # Fallback tool target to pass to `actions_run()`.
        executable = fallback,
        # `FilesToRunProvider` to pass to `ctx.actions.run(executable = ...)`.
        files_to_run = fallback[DefaultInfo].files_to_run,
        # False when falling back to the built-in Python or script tool.
        is_rust = False,
        # Empty prefix when invoking the standalone fallback tool directly.
        prefix_args = [],
        # `None` so fallback tools use the default exec tools or host execution.
        toolchain = None,
    )
