"""Toolchain for the tool that creates self-executable zip files."""

load("//python/private:py_interpreter_program.bzl", "PyInterpreterProgramInfo")
load("//python/private:sentinel_impl.bzl", "SentinelInfo")
load("//python/private:toolchain_types.bzl", "EXE_ZIP_MAKER_TOOLCHAIN_TYPE")

def _py_exe_zip_maker_toolchain_impl(ctx):
    exe_zip_maker = ctx.attr.exe_zip_maker
    if exe_zip_maker != None and SentinelInfo in exe_zip_maker:
        exe_zip_maker = None

    return [
        platform_common.ToolchainInfo(
            exe_zip_maker = exe_zip_maker,
        ),
    ]

py_exe_zip_maker_toolchain = rule(
    implementation = _py_exe_zip_maker_toolchain_impl,
    doc = """Provides the tool used to create self-executable zip files.

This provides `ToolchainInfo` with the following attributes:
* `exe_zip_maker`: {type}`Target | None`. Invoked with three positional
  arguments: `<preamble> <zip> <output>`. Must provide either
  `PyInterpreterProgramInfo` or `DefaultInfo.files_to_run`. If `None`, the
  rules fall back to their built-in implementation.
""",
    attrs = {
        "exe_zip_maker": attr.label(
            # NOTE: This is an executable, but can't use `executable = True`
            # because the `//python:none` sentinel isn't executable.
            # `allow_files = True` (not `allow_single_file`) because binary
            # targets can have multiple files in `DefaultInfo.files`.
            allow_files = True,
            cfg = "exec",
            doc = """
The tool to create self-executable zip files.

To indicate no tool, specify the special target {obj}`//python:none`.
""",
        ),
    },
)

def get_exe_zip_maker(ctx):
    """Returns how to run the tool for creating self-executable zips.

    Prefers the tool from the `exe_zip_maker` toolchain, if one is resolved
    and provides it. Otherwise, falls back to the rule's `_exe_zip_maker`
    attribute.

    Args:
        ctx: The rule context. The rule must declare
            `EXE_ZIP_MAKER_TOOLCHAIN_TYPE` as an optional toolchain and have
            an `_exe_zip_maker` attribute.

    Returns:
        {type}`struct` with fields:
        * `executable`: {type}`Target` to pass to `actions_run()`.
        * `toolchain`: {type}`Label | None` the toolchain type to pass to
          `actions_run()` so the action runs on the exec platform the tool
          was built for. `None` when the tool is a `py_interpreter_program`
          (`actions_run` then uses the exec tools toolchain) or when falling
          back to the attribute.
    """
    toolchain = ctx.toolchains[EXE_ZIP_MAKER_TOOLCHAIN_TYPE]
    if toolchain and toolchain.exe_zip_maker:
        executable = toolchain.exe_zip_maker
        if PyInterpreterProgramInfo in executable:
            return struct(executable = executable, toolchain = None)
        return struct(
            executable = executable,
            toolchain = EXE_ZIP_MAKER_TOOLCHAIN_TYPE,
        )
    return struct(executable = ctx.attr._exe_zip_maker, toolchain = None)
