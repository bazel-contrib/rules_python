"""Rule to build dependencies under a target platform transition."""

def _platform_transition_impl(_settings, attr):
    return {"//command_line_option:platforms": str(attr.target_platform)}

_platform_transition = transition(
    implementation = _platform_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _cross_platform_files_impl(ctx):
    files = depset(
        transitive = [
            dep[DefaultInfo].files
            for dep in ctx.attr.deps
        ] + [
            dep[DefaultInfo].default_runfiles.files
            for dep in ctx.attr.deps
        ],
    )
    return [
        DefaultInfo(
            files = files,
            runfiles = ctx.runfiles(transitive_files = files),
        ),
    ]

cross_platform_files = rule(
    implementation = _cross_platform_files_impl,
    attrs = {
        "deps": attr.label_list(
            cfg = _platform_transition,
            mandatory = True,
        ),
        "target_platform": attr.label(
            mandatory = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
