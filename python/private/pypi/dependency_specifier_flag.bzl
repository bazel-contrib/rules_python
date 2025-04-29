load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//python/private:toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")
load(":pep508_evaluate.bzl", "evaluate")

def depspec_flag(**kwargs):
    pypa_dependency_specification(
        # todo: copied from pep508_env.bzl
        os_name = select({
            # The "java" value is documented, but with Jython defunct,
            # shouldn't occur in practice.
            # The osname value is technically a property of the runtime, not the
            # targetted OS at runtime, but the distinction shouldn't matter in
            # practice.
            "@platforms//os:windows": "nt",
            "//conditions:default": "posix",
        }),
        # todo: copied from pep508_env.bzl
        sys_platform = select({
            "@platforms//os:windows": "win32",
            "@platforms//os:linux": "linux",
            "@platforms//os:osx": "darwin",
            # todo: what does spec say unknown value is?
            "//conditions:default": "",
        }),
        # todo: copied from pep508_env.bzl
        # todo: pep508_env and evaluate have an "aliases" thing that needs
        # to be incorporated
        # todo: there are many more cpus. Unfortunately, it doesn't look like
        # the value is directly accessible to starlark. It might be possible to
        # get it via CcToolchain.cpu though.
        platform_machine = select({
            "@platforms//cpu:x86_64": "x86_64",
            "@platforms//cpu:aarch64": "aarch64",
            # todo: what does spec say unknown value is?
            "//conditions:default": "",
        }),
        # todo: copied from pep508_env.bzl
        platform_system = select({
            "@platforms//os:windows": "Windows",
            "@platforms//os:linux": "Linux",
            "@platforms//os:osx": "Darwin",
            # todo: what does spec say unknown value is?
            "//conditions:default": "",
        }),
        **kwargs
    )

# todo: maybe put all the env into a single target and have a
# PyPiEnvMarkersInfo provider? Have --pypi_env=//some:target?
def _impl(ctx):
    # todo: should unify with pep508_env.bzl
    env = {}

    runtime = ctx.toolchains[TARGET_TOOLCHAIN_TYPE].py3_runtime
    if runtime.interpreter_version_info:
        version_info = runtime.interpreter_version_info
        env["python_version"] = "{major}.{minor}".format(
            major = version_info.major,
            minor = version_info.minor,
        )
        full_version = format_full_version(version_info)
        env["python_full_version"] = full_version
        env["implementation_version"] = full_version
    else:
        env["python_version"] = _get_flag(ctx.attr._python_version)
        full_version = _get_flag(ctx.attr._python_full_version)
        env["python_full_version"] = full_version
        env["implementation_version"] = full_version

    # We assume cpython if the toolchain doesn't specify because it's most
    # likely to be true.
    env["implementation_name"] = runtime.implementation_name or "cpython"
    env["os_name"] = ctx.attr.os_name
    env["sys_platform"] = ctx.attr.sys_platform
    env["platform_machine"] = ctx.attr.platform_machine

    # todo: maybe add PyRuntimeInfo.platform_python_implementation?
    # The values are slightly different to implementation_name.
    # However, digging through old PEPs, it looks like
    # platform.python_implementation is legacy, and sys.implementation.name
    # "replaced" it. Can probably just special case this.
    platform_python_impl = runtime.implementation_name
    if platform_python_impl == "cpython":
        platform_python_impl = "CPython"
    env["platform_python_implementation"] = platform_python_impl
    env["platform_release"] = ctx.attr._platform_release_config_flag[BuildSettingInfo].value
    env["platform_system"] = ctx.attr.platform_system
    env["platform_version"] = ctx.attr._platform_version_config_flag[BuildSettingInfo].value

    if evaluate(ctx.attr.expression, env = env):
        value = "yes"
    else:
        value = "no"
    return [config_common.FeatureFlagInfo(value = value)]

pypa_dependency_specification = rule(
    implementation = _impl,
    attrs = {
        "expression": attr.string(),
        "os_name": attr.string(),
        "sys_platform": attr.string(),
        "platform_machine": attr.string(),
        "platform_system": attr.string(),
        "_platform_release_config_flag": attr.label(
            default = "//python/config_settings:pip_platform_release_config",
        ),
        "_platform_version_config_flag": attr.label(
            default = "//python/config_settings:pip_platform_version_config",
        ),
        "_python_version_flag": attr.label(
            default = "//python/config_settings:python_version_major_minor",
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

# Adapted from spec code at:
# https://packaging.python.org/en/latest/specifications/dependency-specifiers/#environment-markers
def format_full_version(info):
    kind = info.releaselevel
    if kind == "final":
        kind = ""
        serial = ""
    else:
        kind = kind[0] if kind else ""
        serial = str(info.serial) if info.serial else ""

    return "{major}.{minor}.{micro}{kind}{serial}".format(
        v = info,
        major = info.major,
        minor = info.minor,
        micro = info.micro,
        kind = kind,
        serial = serial,
    )

def _get_flag(t):
    if config_common.FeatureFlagInfo in t:
        return t[config_common.FeatureFlagInfo].value
    if BuildSettingInfo in t:
        return t[BuildSettingInfo].value
    fail("Should not occur: {} does not have necessary providers")
