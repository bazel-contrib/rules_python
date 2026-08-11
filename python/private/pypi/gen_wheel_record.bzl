"""Rule for generating platform-specific RECORD files."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//python/private:attributes.bzl", "WINDOWS_CONSTRAINTS_ATTRS")
load("//python/private:common.bzl", "is_windows_platform")

def _gen_wheel_record_impl(ctx):
    is_windows = is_windows_platform(ctx)
    rewriter_file = ctx.files._wheel_record_rewriter[0]
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
            action_exe = (
                ctx.attr._wheel_record_rewriter[DefaultInfo].files_to_run
            )

        action_args.add(in_file)
        action_args.add(out_file)
        action_args.add("windows" if is_windows else "unix")
        action_args.add(data_dir_basename)

        ctx.actions.run(
            inputs = inputs,
            outputs = [out_file],
            executable = action_exe,
            arguments = [action_args],
            mnemonic = "PyRewriteWheelRecord",
            progress_message = "Rewriting wheel RECORD %{output}",
            toolchain = None,
        )

    return [
        DefaultInfo(files = depset(out_files)),
    ]

gen_wheel_record = rule(
    implementation = _gen_wheel_record_impl,
    attrs = dicts.add(
        WINDOWS_CONSTRAINTS_ATTRS,
        {
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
    ),
)
