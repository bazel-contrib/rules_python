"""Config setting for whether a C++ toolchain can build for a platform."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "@rules_cc//cc:find_cc_toolchain.bzl",
    "find_cc_toolchain",
    "use_cc_toolchain",
)

_ProbeInfo = provider(
    doc = "The result of looking for a C++ toolchain.",
    fields = {"available": "bool: whether a usable C++ toolchain was found."},
)

def _probe_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx, mandatory = False)

    # rules_cc registers its Windows toolchains even if their tools are
    # missing, and then runs an error script instead of them, e.g.
    # vc_installation_error_arm64.bat or clang_installation_error.bat.
    available = cc_toolchain != None and (
        "installation_error" not in cc_toolchain.compiler_executable
    )
    return [_ProbeInfo(available = available)]

_probe = rule(
    implementation = _probe_impl,
    toolchains = use_cc_toolchain(mandatory = False),
)

def _platform_transition_impl(_settings, attr):
    return {"//command_line_option:platforms": str(attr.platform)}

_platform_transition = transition(
    implementation = _platform_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _cc_toolchain_available_impl(ctx):
    for constraint in ctx.attr.constraint_values:
        if not ctx.target_platform_has_constraint(
            constraint[platform_common.ConstraintValueInfo],
        ):
            return [config_common.FeatureFlagInfo(value = "no")]

    # With a transition, ctx.attr.probe is a list.
    available = ctx.attr.probe[0][_ProbeInfo].available
    required = (
        ctx.attr.required_flag != None and
        ctx.attr.required_flag[BuildSettingInfo].value
    )
    if required and not available:
        fail((
            "{} is set, but no usable C++ toolchain can build for {}. " +
            "Install one, or unset the flag."
        ).format(ctx.attr.required_flag.label, ctx.attr.platform.label))
    return [config_common.FeatureFlagInfo(value = "yes" if available else "no")]

_cc_toolchain_available = rule(
    implementation = _cc_toolchain_available_impl,
    attrs = {
        "constraint_values": attr.label_list(
            providers = [platform_common.ConstraintValueInfo],
        ),
        "platform": attr.label(
            mandatory = True,
            providers = [platform_common.PlatformInfo],
        ),
        "probe": attr.label(
            cfg = _platform_transition,
            mandatory = True,
            providers = [_ProbeInfo],
        ),
        "required_flag": attr.label(providers = [BuildSettingInfo]),
    },
)

def cc_toolchain_available_config_setting(
        name,
        platform,
        constraint_values = None,
        required_flag = None,
        visibility = None):
    """Matches if a usable C++ toolchain can build for `platform`.

    Toolchain resolution for `platform` finds the toolchain, so the result
    reflects the registered toolchains and execution platforms. A toolchain
    that runs one of rules_cc's error scripts instead of a compiler isn't
    usable.

    Args:
        name: The name of the `config_setting`.
        platform: The platform to look for a C++ toolchain for.
        constraint_values: Constraint values that the target platform must
            also have, as in `config_setting`.
        required_flag: The label of a `bool_flag`. When it's true and the
            target platform has `constraint_values`, a missing or unusable
            toolchain fails the build instead of not matching.
        visibility: The visibility of the `config_setting`.
    """
    constraint_values = constraint_values or []

    _probe(
        name = name + "_probe",
        tags = ["manual"],
        visibility = ["//visibility:private"],
    )
    _cc_toolchain_available(
        name = name + "_flag",
        constraint_values = constraint_values,
        platform = platform,
        probe = ":" + name + "_probe",
        required_flag = required_flag,
        tags = ["manual"],
        visibility = ["//visibility:private"],
    )
    native.config_setting(
        name = name,
        flag_values = {":" + name + "_flag": "yes"},
        visibility = visibility,
    )
