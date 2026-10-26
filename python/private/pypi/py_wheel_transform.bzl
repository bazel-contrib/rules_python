"""Rule for transforming a wheel file or .whldir TreeArtifact using a custom executable."""

load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:common.bzl", "actions_run")
load("//python/private:py_internal.bzl", _py_builtins = "py_internal")
load("//python/private:rule_builders.bzl", "ruleb")
load("//python/private:toolchain_types.bzl", "EXEC_TOOLS_TOOLCHAIN_TYPE")

def _py_wheel_transform_impl(ctx):
    wheel_input = ctx.file.wheel
    out_wheel_dir = ctx.actions.declare_directory(ctx.attr.name + ".whldir")

    args = ctx.actions.args()
    args.add_all("--wheel", [wheel_input], expand_directories = False)
    args.add_all("--out-wheel-dir", [out_wheel_dir], expand_directories = False)
    args.add("--tool", ctx.executable.transform)

    targets = ctx.attr.data + [ctx.attr.transform]
    for key, value in ctx.attr.env.items():
        expanded = _py_builtins.expand_location_and_make_variables(
            ctx = ctx,
            attribute_name = "env[{}]".format(key),
            expression = value,
            targets = targets,
        )
        args.add("--env", "{}={}".format(key, expanded))

    actions_run(
        ctx,
        executable = ctx.attr._wheel_transformer,
        arguments = [args],
        env = {
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONPATH": ctx.file._wheel_layout.dirname,
        },
        inputs = depset(
            [wheel_input, ctx.file._wheel_layout],
            transitive = [dep[DefaultInfo].files for dep in ctx.attr.data],
        ),
        outputs = [out_wheel_dir],
        tools = [ctx.attr.transform[DefaultInfo].files_to_run],
        use_default_shell_env = True,
        mnemonic = "PyWheelTransform",
        progress_message = "Transforming wheel %{input} into %{output}",
    )

    return [DefaultInfo(files = depset([out_wheel_dir]))]

py_wheel_transform = ruleb.Rule(
    implementation = _py_wheel_transform_impl,
    doc = """Runs a user-provided executable to transform a `.whl` file or `.whldir` TreeArtifact.

The transform executable receives the default shell environment (`PATH`, etc.) scrubbed of the
wrapper's `RUNFILES_*` and `PYTHONSAFEPATH`/`PYTHONPATH`/`PYTHONHOME` launcher variables, along with:
- `WHEEL_FILE`: absolute path to the input `.whl` file.
- `WHEEL_OUTPUT_ROOT`: absolute path to the output directory where the single transformed
  `.whl` file must be written.

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
    toolchains = [
        ruleb.ToolchainType(EXEC_TOOLS_TOOLCHAIN_TYPE, mandatory = True),
    ],
    attrs = {
        "data": lambda: attrb.LabelList(
            allow_files = True,
            doc = "Additional data dependencies available to the transform tool.",
        ),
        "env": lambda: attrb.StringDict(
            doc = "Environment variables passed to the transform tool (supports location and make variable expansion).",
        ),
        "transform": lambda: attrb.Label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            doc = "The transform executable to run.",
        ),
        "wheel": lambda: attrb.Label(
            mandatory = True,
            allow_single_file = True,
            doc = "The input `.whl` file or `.whldir` TreeArtifact directory.",
        ),
        "_wheel_layout": lambda: attrb.Label(
            allow_single_file = True,
            default = Label("//python/private/pypi:wheel_layout.py"),
        ),
        "_wheel_transformer": lambda: attrb.Label(
            default = "//python/private/pypi:wheel_transformer",
            executable = True,
            cfg = "exec",
        ),
    },
).build()
