"""Rules to depend on an extra of a PyPI package without knowing its extras.

The dependencies of an extra, e.g. `bar[socks]`, are only known by reading the
`METADATA` of `bar`, which is only available in the whl repository of `bar`.
The hub cannot create the `[socks]` target for every extra that `bar`
provides without fetching the wheels, so the dependency on an extra is wired
as follows:

1. The package that depends on `bar[socks]` creates an {obj}`extra_dep`
   target, which depends on the `_extras` target of `bar` with the
   {obj}`REQUESTED_EXTRA` setting set to `socks`.
2. The whl repository of `bar` creates an {obj}`extra_select` target named
   `_extras`, which selects the `[socks]` target based on the value of the
   setting and resets the setting to its default value, so that the targets of
   the extras are analyzed in the same configuration as the rest of the build.

The hub only needs to forward the `_extras` target of each package to the
right whl repository for the target platform.

Both rules forward the providers of their only dependency, which is in the
`deps` attribute so that the aspects propagating along `deps` reach the
package.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//python/private:py_cc_link_params_info.bzl", "PyCcLinkParamsInfo")
load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:reexports.bzl", "BuiltinPyInfo")

# The name of the target that selects the requested extra of a package.
EXTRAS_SELECT_TARGET = "_extras"

# The setting that carries the requested extra from the {obj}`extra_dep` to the
# {obj}`extra_select` target.
REQUESTED_EXTRA = str(Label("//python/private/pypi:requested_extra"))

# All of the providers of the targets in the whl and hub repositories, i.e.
# `py_library` and `missing_package_error`. `DefaultInfo` is always present.
_FORWARDED_PROVIDERS = [
    p
    for p in [
        PyInfo,
        BuiltinPyInfo,
        PyCcLinkParamsInfo,
        InstrumentedFilesInfo,
        OutputGroupInfo,
    ]
    if p != None
]

def _requested_extra_impl(ctx):
    return [BuildSettingInfo(value = ctx.build_setting_value)]

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

def _forward(ctx):
    if len(ctx.attr.deps) != 1:
        fail("Expected exactly one target in 'deps', got: {}".format(ctx.attr.deps))

    target = ctx.attr.deps[0]
    return [target[DefaultInfo]] + [
        target[provider]
        for provider in _FORWARDED_PROVIDERS
        if provider in target
    ]

def _extra_dep_impl(ctx):
    return _forward(ctx)

extra_dep = rule(
    implementation = _extra_dep_impl,
    doc = """\
Depend on an extra of a PyPI package.

The only target in `deps` is the {obj}`extra_select` target of the package,
which resolves the `extra` to the target that includes the package and the
dependencies of the extra. All of its providers are forwarded.
""",
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            cfg = _set_requested_extra,
            doc = "The {obj}`extra_select` target of the package.",
        ),
        "extra": attr.string(
            mandatory = True,
            doc = "The normalized name of the extra.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def _extra_select_impl(ctx):
    extra = ctx.attr._requested_extra[BuildSettingInfo].value
    if extra and extra not in ctx.attr.extras:
        # This is how `pip` handles the unknown extras.
        # buildifier: disable=print
        print("WARNING: {} does not provide the extra '{}'".format(
            ctx.attr.distribution,
            extra,
        ))

    return _forward(ctx)

extra_select = rule(
    implementation = _extra_select_impl,
    doc = """\
Forward the target of the extra that is requested by an {obj}`extra_dep`.

The `deps` is expected to be a `select` on the {obj}`REQUESTED_EXTRA`
setting that results in a single target. The setting is reset on the edge to
`deps` so that the targets of the extras are analyzed in the same
configuration regardless of how they are reached. All of the providers of
the target are forwarded.
""",
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            cfg = _reset_requested_extra,
            doc = "The target for the requested extra.",
        ),
        "distribution": attr.string(
            doc = "The name and the version of the package for the warning about the unknown extras.",
        ),
        "extras": attr.string_list(
            doc = "The normalized extras that have a target, a warning is printed if any other extra is requested.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
        "_requested_extra": attr.label(
            default = REQUESTED_EXTRA,
        ),
    },
)

def extra_select_targets(
        *,
        name,
        targets,
        default,
        distribution = "",
        native = native,
        rules = None,
        visibility = None):
    """Create the {obj}`extra_select` target and the config settings for the extras.

    Args:
        name: {type}`str` the name of the {obj}`extra_select` target.
        targets: {type}`dict[str, str]` the normalized extras to the labels of
            the targets that include the extra.
        default: {type}`str` the label used when the requested extra is not
            provided by the package, which follows `pip` that only warns about
            unknown extras.
        distribution: {type}`str` the name and the version of the package
            used in the warning about the unknown extras.
        native: the native struct for overriding in tests.
        rules: a struct with the `extra_select` rule for overriding in tests.
        visibility: {type}`list[str]` the visibility of the target.
    """
    rules = rules or struct(extra_select = extra_select)
    deps = {}
    for extra, label in sorted(targets.items()):
        setting = "{}_{}".format(name, extra)
        native.config_setting(
            name = setting,
            flag_values = {REQUESTED_EXTRA: extra},
            visibility = ["//visibility:private"],
        )
        deps[":" + setting] = [label]

    rules.extra_select(
        name = name,
        deps = select(deps | {"//conditions:default": [default]}) if deps else [default],
        distribution = distribution,
        extras = sorted(targets),
        visibility = visibility,
    )
