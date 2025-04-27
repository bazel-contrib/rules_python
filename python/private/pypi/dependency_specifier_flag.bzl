load("//python/private:toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")
load(":pep508_evaluate.bzl", "evaluate")

def _impl(ctx):
    env = {}

    runtime = ctx.toolchains[TARGET_TOOLCHAIN_TYPE].py3_runtime
    if runtime.interpreter_version_info:
        version_info = runtime.interpreter_version_info
        env["python_version"] = "{v.major}.{v.minor}".format(v = version_info)
        full_version = format_full_version(version_info)
        env["python_full_version"] = full_version
        env["implementation_version"] = full_version
    else:
        env["python_version"] = get_flag(ctx.attr._python_version)
        full_version = get_flag(ctx.attr._python_full_version)
        env["python_full_version"] = full_version
        env["implementation_version"] = full_version

    # We assume cpython if the toolchain doesn't specify because it's most
    # likely to be true.
    env["implementation_name"] = runtime.implementation_name or "cpython"

    # todo: map from os constraint
    env["os_name"] = struct()

    # todo: map from os constraint
    env["sys_platform"] = struct()

    # todo: map from cpu flag (x86_64, etc)
    env["platform_machine"] = struct()

    # todo: add PyRuntimeInfo.platform_python_implementation
    # The values are slightly different to implementation_name
    env["platform_python_implementation"] = runtime.implementation_name

    # todo: add flag to carry this
    env["platform_release"] = struct()

    # todo: map from os constraint
    env["platform_system"] = struct()

    # todo: add flag to carry this
    env["platform_version"] = struct()

    if evalute(ctx.attr.expression, env):
        value = "yes"
    else:
        value = "no"
    return [config_common.FeatureFlagInfo(value = value)]

# Adapted from spec code at:
# https://packaging.python.org/en/latest/specifications/dependency-specifiers/#environment-markers
def format_full_info(info):
    kind = info.releaselevel
    if kind == "final":
        kind = ""
        serial = ""
    else:
        kind = kind[0] if kind else ""
        serial = str(info.serial) if info.serial else ""

    return "{v.major}.{v.minor}.{v.micro}{kind}{serial}".format(
        v = version_info,
        kind = kind,
        serial = serial,
    )
    return version

pypa_dependency_specification = rule(
    implementation = _impl,
    attrs = {
        "expression": attt.string(),
        "_os_name": attr.label(),
        "_sys_platform_flag": attr.label(),
        "_platform_release_flag": attr.label(),
        "_platform_system_flag": attr.label(),
        "_platform_version_flag": attr.label(),
        "_python_version_flag": attr.label(
            default = "//python/config_settings:_python_version_major_minor",
        ),
        "_python_full_version_flag": attr.label(
            default = "//python/config_settings:python_version",
        ),
        "_extra_flag": attr.label(),
    },
    toolchains = [
        TARGET_TOOLCHAIN_TYPE,
    ],
)

def _get_flag(t):
    if config_common.FeatureFlagInfo in t:
        return t[config_common.FeatureFlagInfo].value
    if BuildSettingInfo in t:
        return t[BuildSettingInfo].value
    fail("Should not occur: {} does not have necessary providers")
