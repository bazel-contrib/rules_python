"""Analysis assertions for target and exec configuration propagation."""

VersionInfo = provider("Observed version propagation through the fixture graph.", fields = ["value", "native", "tool"])

def _probe_impl(ctx):
    return [VersionInfo(
        value = ctx.attr.value,
        native = [dep[VersionInfo].value for dep in ctx.attr.deps],
        tool = ctx.attr.tool[VersionInfo].value if ctx.attr.tool else None,
    )]

probe = rule(implementation = _probe_impl, attrs = {
    "deps": attr.label_list(),
    "tool": attr.label(cfg = "exec"),
    "value": attr.string(),
})

def _transition_impl(_settings, attr):
    return {"@rules_python//python/config_settings:python_version": attr.version}

_version_transition = transition(implementation = _transition_impl, inputs = [], outputs = ["@rules_python//python/config_settings:python_version"])

def _check_impl(ctx):
    info = ctx.attr.target[0][VersionInfo]
    expected_native = ctx.attr.version if ctx.attr.native_version == "inherit" else ctx.attr.native_version
    if info.value != ctx.attr.version or info.native != [expected_native] or info.tool != ctx.attr.version:
        fail("Expected binding/tool %s, native %s; got %s" % (ctx.attr.version, expected_native, info))
    return [DefaultInfo()]

check = rule(implementation = _check_impl, attrs = {
    "native_version": attr.string(default = "inherit"),
    "target": attr.label(cfg = _version_transition),
    "version": attr.string(),
    "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
})
