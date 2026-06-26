"""Rule for generating an execution-phase action failure when a PyPI package is missing."""

load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:reexports.bzl", "BuiltinPyInfo")

def _missing_package_error_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".error")

    # Register an action that fails when Bazel attempts to stage/build this file
    ctx.actions.run_shell(
        outputs = [out],
        command = "echo 'ERROR: PyPI package \"{pkg}\" is not available{hub_clause}.' >&2 && exit 1".format(
            pkg = ctx.attr.package_name,
            hub_clause = (' when building under PyPI hub "%s"' % ctx.attr.hub_name) if ctx.attr.hub_name else " because no PyPI hub or default hub is requested",
        ),
    )

    maybe_builtin = [BuiltinPyInfo(transitive_sources = depset([out]))] if BuiltinPyInfo != None else []

    return [
        DefaultInfo(
            files = depset([out]),
            data_runfiles = ctx.runfiles([out]),
        ),
        PyInfo(
            transitive_sources = depset([out]),
        ),
    ] + maybe_builtin

missing_package_error = rule(
    implementation = _missing_package_error_impl,
    attrs = {
        "hub_name": attr.string(mandatory = True),
        "package_name": attr.string(mandatory = True),
    },
)
