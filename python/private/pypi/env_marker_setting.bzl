"""Implement a flag for matching the dependency specifiers at analysis time."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//python/private:toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")
load(":pep508_evaluate.bzl", "evaluate")

# TODO @aignas 2025-04-29: this is copied from ./pep508_env.bzl
_platform_machine_aliases = {
    # These pairs mean the same hardware, but different values may be used
    # on different host platforms.
    "amd64": "x86_64",
    "arm64": "aarch64",
    "i386": "x86_32",
    "i686": "x86_32",
}

def env_marker_setting(**kwargs):
    _env_marker_setting(
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
            # Taken from
            # https://docs.python.org/3/library/sys.html#sys.platform
            "@platforms//os:android": "android",
            "@platforms//os:emscripten": "emscripten",
            # NOTE, the below values here are from the time when the Python
            # interpreter is built and it is hard to know for sure, maybe this
            # should be something from the toolchain?
            "@platforms//os:freebsd": "freebsd8",
            "@platforms//os:ios": "ios",
            "@platforms//os:linux": "linux",
            "@platforms//os:openbsd": "openbsd6",
            "@platforms//os:osx": "darwin",
            "@platforms//os:wasi": "wasi",
            "@platforms//os:windows": "win32",
            "//conditions:default": "",
        }),
        # todo: copied from pep508_env.bzl
        # TODO: there are many cpus and unfortunately, it doesn't look like
        # the value is directly accessible to starlark. It might be possible to
        # get it via CcToolchain.cpu though.
        platform_machine = select({
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
        }),
        # todo: copied from pep508_env.bzl
        platform_system = select({
            # See https://peps.python.org/pep-0738/#platform
            "@platforms//os:android": "Android",
            "@platforms//os:freebsd": "FreeBSD",
            # See https://peps.python.org/pep-0730/#platform
            "@platforms//os:ios": "iOS",  # can also be iPadOS?
            "@platforms//os:linux": "Linux",
            "@platforms//os:netbsd": "NetBSD",
            "@platforms//os:openbsd": "OpenBSD",
            "@platforms//os:osx": "Darwin",
            "@platforms//os:windows": "Windows",
            # The value is empty string if it cannot be determined:
            # https://docs.python.org/3/library/platform.html#platform.machine
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

    # NOTE: Platform release for Android will be Android version:
    # https://peps.python.org/pep-0738/#platform
    # Similar for iOS:
    # https://peps.python.org/pep-0730/#platform
    env["platform_release"] = ctx.attr._platform_release_config_flag[BuildSettingInfo].value
    env["platform_system"] = ctx.attr.platform_system
    env["platform_version"] = ctx.attr._platform_version_config_flag[BuildSettingInfo].value

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
    implementation = _impl,
    attrs = {
        "expression": attr.string(),
        "os_name": attr.string(),
        "platform_machine": attr.string(),
        "platform_system": attr.string(),
        "sys_platform": attr.string(),
        # todo: what to do with this?
        # NOTE(aignas) - with the `evaluate` function we can evaluate a
        # particular value. For example we can have an expression and just
        # evaluate extras. I.e. if the extras don't match, then the whole thing
        # is false, if it matches, then it is a string with a remaining
        # expression. This means that the `pypa_dependency_specification`
        # should not receive any `extra_flags` because these are not properties
        # of the target configuration, but rather of a particular package,
        # hence we could drop it.
        "_extra_flag": attr.label(),
        "_platform_release_config_flag": attr.label(
            default = "//python/config_settings:pip_platform_release_config",
        ),
        "_platform_version_config_flag": attr.label(
            default = "//python/config_settings:pip_platform_version_config",
        ),
        "_python_full_version_flag": attr.label(
            default = "//python/config_settings:python_version",
        ),
        "_python_version_flag": attr.label(
            default = "//python/config_settings:python_version_major_minor",
        ),
    },
    provides = [config_common.FeatureFlagInfo],
    toolchains = [
        TARGET_TOOLCHAIN_TYPE,
    ],
)

def format_full_version(info):
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
