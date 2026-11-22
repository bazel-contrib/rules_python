"""Rule for generating an execution-phase action failure when a PyPI package is missing."""

load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:reexports.bzl", "BuiltinPyInfo")

def _error(ctx, message):
    out = ctx.actions.declare_file(ctx.label.name + ".error")

    # Register an action that fails when Bazel attempts to stage/build this file
    ctx.actions.run_shell(
        outputs = [out],
        command = "echo \"$1\" >&2 && exit 1",
        arguments = ["ERROR: " + message],
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

def _missing_package_error_impl(ctx):
    if ctx.attr.hub_name:
        hub_clause = ' when building under PyPI hub "{hub}". Try adding it to the requirements of this hub (e.g. requirements_lock or requirements_by_platform in pip.parse)'.format(
            hub = ctx.attr.hub_name,
        )
    else:
        hub_clause = ' because no default PyPI hub was configured. Try designating a default hub via pip.default(default_hub = "...") or select a hub using --@rules_python//python/config_settings:venv'

    return _error(ctx, 'PyPI package "{pkg}" is not available{hub_clause}.'.format(
        pkg = ctx.attr.package_name,
        hub_clause = hub_clause,
    ))

missing_package_error = rule(
    implementation = _missing_package_error_impl,
    attrs = {
        "hub_name": attr.string(mandatory = True),
        "package_name": attr.string(mandatory = True),
    },
)
