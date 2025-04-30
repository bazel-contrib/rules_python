"""Implement a flag for matching the dependency specifiers at analysis time."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//python/private:toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")
load(":pep508_evaluate.bzl", "evaluate")

# todo: copied from pep508_env.bzl
_os_name_select_map = {
    # The "java" value is documented, but with Jython defunct,
    # shouldn't occur in practice.
    # The os.name value is technically a property of the runtime, not the
    # targetted runtime OS, but the distinction shouldn't matter if
    # things are properly configured.
    "@platforms//os:windows": "nt",
    "//conditions:default": "posix",
}

# TODO @aignas 2025-04-29: this is copied from ./pep508_env.bzl
_platform_machine_aliases = {
    # These pairs mean the same hardware, but different values may be used
    # on different host platforms.
    "amd64": "x86_64",
    "arm64": "aarch64",
    "i386": "x86_32",
    "i686": "x86_32",
}

# Taken from
# https://docs.python.org/3/library/sys.html#sys.platform
_sys_platform_select_map = {
    # These values are decided by the sys.platform docs.
    "@platforms//os:android": "android",
    "@platforms//os:emscripten": "emscripten",
    "@platforms//os:ios": "ios",
    "@platforms//os:linux": "linux",
    "@platforms//os:osx": "darwin",
    "@platforms//os:windows": "win32",
    "@platforms//os:wasi": "wasi",
    # NOTE: The below values are approximations. The sys.platform() docs
    # don't have documented values for these OSes. Per docs, the
    # sys.platform() value reflects the OS at the time Python was *built*
    # instead of the runtime (target) OS value.
    "@platforms//os:freebsd": "freebsd",
    "@platforms//os:openbsd": "openbsd",
    # For lack of a better option, use empty string. No standard doc/spec
    # about sys_platform value.
    "//conditions:default": "",
}

# todo: copied from pep508_env.bzl
# TODO: there are many cpus and unfortunately, it doesn't look like
# the value is directly accessible to starlark. It might be possible to
# get it via CcToolchain.cpu though.
_platform_machine_select_map = {
    "@platforms//cpu:aarch32": "aarch32",
    "@platforms//cpu:aarch64": "aarch64",
    "@platforms//cpu:arm": "arm",
    "@platforms//cpu:arm64": "arm64",
    "@platforms//cpu:arm64_32": "arm64_32",
    "@platforms//cpu:arm64e": "arm64e",
    "@platforms//cpu:armv6-m": "armv6-m",
    "@platforms//cpu:armv7": "armv7",
    "@platforms//cpu:armv7-m": "armv7-m",
    "@platforms//cpu:armv7e-m": "armv7e-m",
    "@platforms//cpu:armv7e-mf": "armv7e-mf",
    "@platforms//cpu:armv7k": "armv7k",
    "@platforms//cpu:armv8-m": "armv8-m",
    "@platforms//cpu:cortex-r52": "cortex-r52",
    "@platforms//cpu:cortex-r82": "cortex-r82",
    "@platforms//cpu:i386": "i386",
    "@platforms//cpu:mips64": "mips64",
    "@platforms//cpu:ppc": "ppc",
    "@platforms//cpu:ppc32": "ppc32",
    "@platforms//cpu:ppc64le": "ppc64le",
    "@platforms//cpu:riscv32": "riscv32",
    "@platforms//cpu:riscv64": "riscv64",
    "@platforms//cpu:s390x": "s390x",
    "@platforms//cpu:wasm32": "wasm32",
    "@platforms//cpu:wasm64": "wasm64",
    "@platforms//cpu:x86_32": "x86_32",
    "@platforms//cpu:x86_64": "x86_64",
    # The value is empty string if it cannot be determined:
    # https://docs.python.org/3/library/platform.html#platform.machine
    "//conditions:default": "",
}

# todo: copied from pep508_env.bzl
_platform_system_select_map = {
    # See https://peps.python.org/pep-0738/#platform
    "@platforms//os:android": "Android",
    "@platforms//os:freebsd": "FreeBSD",
    # See https://peps.python.org/pep-0730/#platform
    # NOTE: Per Pep 730, "iPadOS" is also an acceptable value
    "@platforms//os:ios": "iOS",
    "@platforms//os:linux": "Linux",
    "@platforms//os:netbsd": "NetBSD",
    "@platforms//os:openbsd": "OpenBSD",
    "@platforms//os:osx": "Darwin",
    "@platforms//os:windows": "Windows",
    # The value is empty string if it cannot be determined:
    # https://docs.python.org/3/library/platform.html#platform.machine
    "//conditions:default": "",
}

def env_marker_setting(**kwargs):
    """Creates an env_marker setting.

    Args:
        name: {type}`str` target name
        expression: {type}`str` the environment marker string to evaluate
        **kwargs: {type}`dict` additionally common kwargs.
    """
    _env_marker_setting(
        name = name,
        expression = expression,
        os_name = select(_os_name_select_map),
        sys_platform = select(_sys_platform_select_map),
        platform_machine = select(_platform_machine_select_map),
        platform_system = select(_platform_system_select_map),
        **kwargs
    )

# todo: maybe put all the env into a single target and have a
# PyPiEnvMarkersInfo provider? Have --pypi_env=//some:target?
def _env_marker_setting_impl(ctx):
    # todo: should unify with pep508_env.bzl
    env = {}

    runtime = ctx.toolchains[TARGET_TOOLCHAIN_TYPE].py3_runtime
    if runtime.interpreter_version_info:
        version_info = runtime.interpreter_version_info
        env["python_version"] = "{major}.{minor}".format(
            major = version_info.major,
            minor = version_info.minor,
        )
        full_version = _format_full_version(version_info)
        env["python_full_version"] = full_version
        env["implementation_version"] = full_version
    else:
        env["python_version"] = _get_flag(ctx.attr._python_version_major_minor_flag)
        full_version = _get_flag(ctx.attr._python_full_version)
        env["python_full_version"] = full_version
        env["implementation_version"] = full_version

    # We assume cpython if the toolchain doesn't specify because it's most
    # likely to be true.
    env["implementation_name"] = runtime.implementation_name or "cpython"
    env["os_name"] = ctx.attr.os_name
    env["sys_platform"] = ctx.attr.sys_platform
    env["platform_machine"] = ctx.attr.platform_machine

    # The `platform_python_implementation` marker value is supposed to come from
    # `platform.python_implementation()`, however, PEP 421 introduced
    # `sys.implementation.name` to replace it. There's now essentially just two
    # possible values it might have: CPython or PyPy. Rather than add a field to
    # the toolchain, we just special case the value from
    # `sys.implementation.name`
    platform_python_impl = runtime.implementation_name
    if platform_python_impl == "cpython":
        platform_python_impl = "CPython"
    elif platform_python_impl == "pypy":
        platform_python_impl = "PyPy"
    env["platform_python_implementation"] = platform_python_impl

    # NOTE: Platform release for Android will be Android version:
    # https://peps.python.org/pep-0738/#platform
    # Similar for iOS:
    # https://peps.python.org/pep-0730/#platform
    env["platform_release"] = _get_flag(ctx.attr._platform_release_config_flag)
    env["platform_system"] = ctx.attr.platform_system
    env["platform_version"] = _get_flag(ctx.attr._platform_version_config_flag)

    # TODO @aignas 2025-04-29: figure out how to correctly share the aliases
    # between the two. Maybe the select statements above should be part of the
    # `pep508_env.bzl` file?
    env = env | {
        "_aliases": {
            "platform_machine": _platform_machine_aliases,
        },
    }

    if evaluate(ctx.attr.expression, env = env):
        # todo: better return value than "yes" and "no"
        # matched/unmatched, satisfied/unsatisfied ?
        value = "yes"
    else:
        value = "no"
    return [config_common.FeatureFlagInfo(value = value)]

_env_marker_setting = rule(
    doc = """
Evaluates an environment marker expression using target configuration info.

See
https://packaging.python.org/en/latest/specifications/dependency-specifiers
for the specification of behavior.
""",
    implementation = _env_marker_setting_impl,
    attrs = {
        "expression": attr.string(
            mandatory = True,
            doc = "Environment marker expression to evaluate.",
        ),
        "os_name": attr.string(),
        "platform_machine": attr.string(),
        "platform_system": attr.string(),
        "sys_platform": attr.string(),
        "_platform_release_config_flag": attr.label(
            default = "//python/config_settings:pip_platform_release_config",
            providers = [[config_common.FeatureFlagInfo], [BuildSettingInfo]],
        ),
        "_platform_version_config_flag": attr.label(
            default = "//python/config_settings:pip_platform_version_config",
            providers = [[config_common.FeatureFlagInfo], [BuildSettingInfo]],
        ),
        "_python_full_version_flag": attr.label(
            default = "//python/config_settings:python_version",
            providers = [config_common.FeatureFlagInfo],
        ),
        "_python_version_major_minor_flag": attr.label(
            default = "//python/config_settings:python_version_major_minor",
            providers = [config_common.FeatureFlagInfo],
        ),
    },
    provides = [config_common.FeatureFlagInfo],
    toolchains = [
        TARGET_TOOLCHAIN_TYPE,
    ],
)

def _format_full_version(info):
    """Format the full python interpreter version.

    Adapted from spec code at:
    https://packaging.python.org/en/latest/specifications/dependency-specifiers/#environment-markers

    Args:
        info: The provider from the Python runtime.

    Returns:
        a {type}`str` with the version
    """
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
