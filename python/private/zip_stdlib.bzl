"""Rule for creating a zipped Python standard library."""

def _zip_stdlib_impl(ctx):
    output = ctx.actions.declare_file(ctx.attr.out)
    strip_prefix = ctx.attr.strip_prefix.strip("/")

    def _map_entry(file):
        # In Bazel, files in external repositories have short_path starting with
        # "../<repo_name>/". Strip that to obtain the repo-relative path.
        path = file.short_path
        if path.startswith("../"):
            path = path.split("/", 2)[2]

        if strip_prefix:
            if path == strip_prefix:
                path = ""
            elif path.startswith(strip_prefix + "/"):
                path = path[len(strip_prefix) + 1:]
            else:
                fail("File '{}' does not start with strip_prefix '{}'".format(
                    file.short_path,
                    strip_prefix,
                ))
        return path + "=" + file.path

    manifest = ctx.actions.args()
    manifest.use_param_file("@%s", use_always = True)
    manifest.set_param_file_format("multiline")
    manifest.add_all(
        ctx.files.srcs,
        map_each = _map_entry,
        allow_closure = True,
    )

    # Zipper operation mode flags:
    # 'c': create a new zip archive
    # 'C': compress files (deflate) rather than storing uncompressed
    zip_cli_args = ctx.actions.args()
    zip_cli_args.add("cC")
    zip_cli_args.add(output)

    ctx.actions.run(
        executable = ctx.executable._zipper,
        arguments = [zip_cli_args, manifest],
        inputs = depset(ctx.files.srcs),
        outputs = [output],
        use_default_shell_env = True,
        mnemonic = "ZipStdlib",
        progress_message = "Building Python stdlib zip %{output}",
    )

    return [DefaultInfo(files = depset([output]))]

zip_stdlib = rule(
    doc = """Creates a zip file containing the standard library files.

The resulting zip archive can be passed to py_runtime so that Python
finds and imports standard library modules from the archive.""",
    implementation = _zip_stdlib_impl,
    attrs = {
        "out": attr.string(
            mandatory = True,
            doc = "The path of the output zip file.",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "The list of files to zip.",
        ),
        "strip_prefix": attr.string(
            default = "",
            doc = "Prefix to strip from input file paths before zipping.",
        ),
        "_zipper": attr.label(
            default = Label("@bazel_tools//tools/zip:zipper"),
            cfg = "exec",
            executable = True,
            allow_files = True,
        ),
    },
)
