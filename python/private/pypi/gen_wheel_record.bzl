"""Rule for generating platform-specific RECORD files."""

load("//python/private:attributes.bzl", "WINDOWS_CONSTRAINTS_PLAIN_ATTRS")
load("//python/private:common.bzl", "is_windows_platform")
load("//python/private:toolchain_types.bzl", "SHRUBBERY_TOOLCHAIN_TYPE")
load("//python/private/toolchains:shrubbery_toolchain.bzl", "get_shrubbery_tool")

def _gen_wheel_record_impl(ctx):
    is_windows = is_windows_platform(ctx)
    tool = get_shrubbery_tool(
        ctx,
        "wheel_record_rewriter",
        ctx.attr._wheel_record_rewriter,
    )
    rewriter_file = None if tool.is_rust else ctx.files._wheel_record_rewriter[0]
    out_files = []

    for in_file in ctx.files.srcs:
        dist_info_name = in_file.dirname.rpartition("/")[2]
        if dist_info_name:
            if dist_info_name.endswith(".dist-info"):
                data_dir_basename = (
                    dist_info_name[:-len(".dist-info")] + ".data"
                )
            else:
                data_dir_basename = dist_info_name + ".data"
            out_file = ctx.actions.declare_file(
                "site-packages/{}/RECORD".format(dist_info_name),
            )
        else:
            data_dir_basename = "data"
            out_file = ctx.actions.declare_file("site-packages/RECORD")

        out_files.append(out_file)

        action_args = ctx.actions.args()
        if tool.is_rust:
            inputs = depset([in_file])
            action_exe = tool.files_to_run
            action_toolchain = tool.toolchain
            action_args.add_all(tool.prefix_args)
        else:
            inputs = depset([in_file, rewriter_file])
            action_toolchain = None
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
                action_exe = tool.files_to_run

        action_args.add(in_file)
        action_args.add(out_file)
        action_args.add("windows" if is_windows else "unix")
        action_args.add(data_dir_basename)
        action_args.add_all(ctx.attr.rewritten_scripts)

        ctx.actions.run(
            inputs = inputs,
            outputs = [out_file],
            executable = action_exe,
            arguments = [action_args],
            mnemonic = "PyRewriteWheelRecord",
            progress_message = "Rewriting wheel RECORD %{output}",
            toolchain = action_toolchain,
        )

    return [
        DefaultInfo(files = depset(out_files)),
    ]

gen_wheel_record = rule(
    implementation = _gen_wheel_record_impl,
    attrs = WINDOWS_CONSTRAINTS_PLAIN_ATTRS | {
        "rewritten_scripts": attr.string_list(
            doc = "List of script names that had shebang rewriting applied.",
            default = [],
        ),
        "srcs": attr.label_list(
            doc = "The original RECORD files to rewrite.",
            mandatory = True,
            allow_files = True,
        ),
        "_wheel_record_rewriter": attr.label(
            default = "//python/private/pypi:wheel_record_rewriter",
            allow_files = True,
            cfg = "exec",
        ),
    },
    toolchains = [
        config_common.toolchain_type(SHRUBBERY_TOOLCHAIN_TYPE, mandatory = False),
    ],
)
