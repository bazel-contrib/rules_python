"""Implementation of the `vendor_uv_lock` macro."""

load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("//python:py_binary.bzl", "py_binary")

_TOOL = Label("//python/uv/private:vendor_uv_lock.py")

def _vendor_uv_lock_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".bzl")
    args = ctx.actions.args()
    args.add("build")
    args.add("--src", ctx.file.src)
    args.add("--out", out)
    args.add("--constant", ctx.attr.constant)
    args.add("--src_label", ctx.attr.src_label)
    args.add("--update_target", ctx.attr.update_target)
    ctx.actions.run(
        executable = ctx.executable._tool,
        arguments = [args],
        inputs = [ctx.file.src],
        outputs = [out],
        mnemonic = "PyVendorUvLock",
        progress_message = "Vendoring %{input} as a .bzl file",
    )
    return [DefaultInfo(files = depset([out]))]

_vendor_uv_lock = rule(
    implementation = _vendor_uv_lock_impl,
    attrs = {
        "constant": attr.string(mandatory = True),
        "src": attr.label(mandatory = True, allow_single_file = [".lock"]),
        "src_label": attr.string(mandatory = True),
        "update_target": attr.string(mandatory = True),
        "_tool": attr.label(
            default = "//python/uv/private:vendor_uv_lock_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Vendor a `uv.lock` file as a `.bzl` file in a build action.",
)

def vendor_uv_lock(
        *,
        name,
        lock,
        src = "uv.lock",
        out = "uv_lock.bzl",
        constant = "UV_LOCK_JSON",
        **kwargs):
    """Vendor a `uv.lock` file as a JSON string constant in a `.bzl` file.

    WORKSPACE macros cannot read files, so this makes the `uv.lock` file
    available to them, e.g. `json.decode(UV_LOCK_JSON)`. The vendored data is
    a subset of the `uv.lock` file, which has only the fields that are needed
    for selecting the distributions, with one package and one distribution
    per line.

    This macro creates the following targets:
    - `name`: the `.bzl` file vendored from `src` in a build action.
    - `name.update`: runs the `.update` target of the {obj}`lock` and then
      updates `out` in the source tree, so a single command updates both
      files.
    - `name.run`: the same, but runs the `.run` target of the {obj}`lock`
      and passes the args to it.
    - `name_test`: a `diff_test` that `out` is up to date. It only depends on
      `src`, so it does not need the network.

    Args:
        name: {type}`str` the name of the targets.
        lock: {type}`str` the name of the {obj}`lock` target in the same
            package that updates `src`, e.g. `requirements` for
            `lock(name = "requirements")`.
        src: {type}`str` the `uv.lock` file, relative to the package.
        out: {type}`str` the vendored `.bzl` file, relative to the package.
        constant: {type}`str` the name of the JSON string constant.
        **kwargs: common kwargs passed to the rules.

    :::{versionadded} VERSION_NEXT_FEATURE
    :::
    """
    pkg = native.package_name()
    prefix = pkg + "/" if pkg else ""
    update_target = "//{}:{}.update".format(pkg, name)
    common_args = [
        "--src={}{}".format(prefix, src),
        "--out={}{}".format(prefix, out),
        "--constant={}".format(constant),
        "--src_label=//{}:{}".format(pkg, src),
        "--update_target={}".format(update_target),
    ]

    _vendor_uv_lock(
        name = name,
        src = src,
        constant = constant,
        src_label = "//{}:{}".format(pkg, src),
        update_target = update_target,
        **kwargs
    )

    tags = ["manual"] + kwargs.pop("tags", [])
    for suffix in ["update", "run"]:
        runner = ":{}.{}".format(lock, suffix)
        py_binary(
            name = "{}.{}".format(name, suffix),
            srcs = [_TOOL],
            main = _TOOL,
            args = ["update"] + common_args + [
                "--lock_runner=$(rlocationpath {})".format(runner),
            ],
            data = [runner],
            deps = [Label("//python/uv/private:vendor_uv_lock_lib")],
            tags = tags,
            **kwargs
        )

    diff_test(
        name = name + "_test",
        file1 = out,
        file2 = name,
        failure_message = "Run `bazel run {}`".format(update_target),
        **kwargs
    )
