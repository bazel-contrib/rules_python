"""Rules to depend on an extra of a PyPI package without knowing its extras.

The dependencies of an extra, e.g. `bar[socks]`, are only known by reading the
`METADATA` of `bar`, which is only available in the whl repository of `bar`.
Instead of creating the targets for the extras in the hub, which would require
the hub to know the extras that each package provides, the dependency on an
extra is wired as follows:

1. The package that depends on `bar[socks]` creates an {obj}`extra_dep`
   target, which depends on the `_extras` target of `bar` with the
   {obj}`REQUESTED_EXTRA` setting set to `socks`.
2. The whl repository of `bar` creates an {obj}`extra_select` target named
   `_extras`, which selects the `[socks]` target based on the value of the
   setting and resets the setting to its default value, so that the targets of
   the extras are analyzed in the same configuration as the rest of the build.

The hub only needs to forward the `_extras` target of each package to the
right whl repository for the target platform.
"""

load("//python/private:py_cc_link_params_info.bzl", "PyCcLinkParamsInfo")
load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:reexports.bzl", "BuiltinPyInfo")

# The name of the target that selects the requested extra of a package.
EXTRAS_SELECT_TARGET = "_extras"

# The setting that carries the requested extra from the {obj}`extra_dep` to the
# {obj}`extra_select` target.
REQUESTED_EXTRA = str(Label("//python/private/pypi:requested_extra"))

def _requested_extra_impl(_ctx):
    return []

requested_extra = rule(
    implementation = _requested_extra_impl,
    build_setting = config.string(flag = False),
    doc = """\
The normalized name of the extra requested by an {obj}`extra_dep` target.

This is only set on the edge between {obj}`extra_dep` and the
{obj}`extra_select` target and it is reset by the {obj}`extra_select` target.
""",
)

def _set_requested_extra_impl(_settings, attr):
    return {REQUESTED_EXTRA: attr.extra}

_set_requested_extra = transition(
    implementation = _set_requested_extra_impl,
    inputs = [],
    outputs = [REQUESTED_EXTRA],
)

def _reset_requested_extra_impl(_settings, _attr):
    return {REQUESTED_EXTRA: ""}

_reset_requested_extra = transition(
    implementation = _reset_requested_extra_impl,
    inputs = [],
    outputs = [REQUESTED_EXTRA],
)

def _forward(ctx, target, attr_name):
    if type(target) == type([]):
        target = target[0]

    default_info = target[DefaultInfo]
    providers = [
        DefaultInfo(
            files = default_info.files,
            default_runfiles = default_info.default_runfiles,
            data_runfiles = default_info.data_runfiles,
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = [attr_name],
        ),
    ]
    for provider in [PyInfo, BuiltinPyInfo, PyCcLinkParamsInfo]:
        if provider != None and provider in target:
            providers.append(target[provider])

    return providers

def _extra_dep_impl(ctx):
    return _forward(ctx, ctx.attr.pkg, "pkg")

extra_dep = rule(
    implementation = _extra_dep_impl,
    doc = """\
Depend on an extra of a PyPI package.

The `pkg` is the {obj}`extra_select` target of the package, which resolves the
`extra` to the target that includes the package and the dependencies of the
extra.

""",
    attrs = {
        "extra": attr.string(
            mandatory = True,
            doc = "The normalized name of the extra.",
        ),
        "pkg": attr.label(
            mandatory = True,
            cfg = _set_requested_extra,
            doc = "The {obj}`extra_select` target of the package.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def _extra_select_impl(ctx):
    return _forward(ctx, ctx.attr.actual, "actual")

extra_select = rule(
    implementation = _extra_select_impl,
    doc = """\
Forward the target of the extra that is requested by an {obj}`extra_dep`.

The `actual` is expected to be a `select` on the {obj}`REQUESTED_EXTRA`
setting. The setting is reset on the edge to `actual` so that the targets of
the extras are analyzed in the same configuration regardless of how they are
reached.

""",
    attrs = {
        "actual": attr.label(
            mandatory = True,
            cfg = _reset_requested_extra,
            doc = "The target for the requested extra.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def extra_select_targets(*, name, targets, default, native = native, rules = None, visibility = None):
    """Create the {obj}`extra_select` target and the config settings for the extras.

    Args:
        name: {type}`str` the name of the {obj}`extra_select` target.
        targets: {type}`dict[str, str]` the normalized extras to the labels of
            the targets that include the extra.
        default: {type}`str` the label used when the requested extra is not
            provided by the package, which follows `pip` that only warns about
            unknown extras.
        native: the native struct for overriding in tests.
        rules: a struct with the `extra_select` rule for overriding in tests.
        visibility: {type}`list[str]` the visibility of the target.
    """
    rules = rules or struct(extra_select = extra_select)
    actual = {}
    for extra, label in sorted(targets.items()):
        setting = "{}_{}".format(name, extra)
        native.config_setting(
            name = setting,
            flag_values = {REQUESTED_EXTRA: extra},
            visibility = ["//visibility:private"],
        )
        actual[":" + setting] = label

    rules.extra_select(
        name = name,
        actual = select(actual | {"//conditions:default": default}) if actual else default,
        visibility = visibility,
    )
