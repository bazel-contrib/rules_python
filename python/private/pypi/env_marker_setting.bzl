"""Implement a flag for matching the dependency specifiers at analysis time."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//python/private:toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")
load(
    ":pep508_env.bzl",
    "env_aliases",
    "os_name_select_map",
    "platform_machine_select_map",
    "platform_system_select_map",
    "sys_platform_select_map",
)
load(":pep508_evaluate.bzl", "evaluate")

# Use capitals to hint its not an actual boolean type.
_ENV_MARKER_TRUE = "TRUE"
_ENV_MARKER_FALSE = "FALSE"

def env_marker_setting(*, name, expression, **kwargs):
    """Creates an env_marker setting.

    Generated targets:

    * `is_{name}_true`: config_setting that matches when the expression is true.
    * `{name}`: env marker target that evalutes the expression.

    Args:
        name: {type}`str` target name
        expression: {type}`str` the environment marker string to evaluate
        **kwargs: {type}`dict` additional common kwargs.
    """
    native.config_setting(
        name = "is_{}_true".format(name),
        flag_values = {
            ":{}".format(name): _ENV_MARKER_TRUE,
        },
        **kwargs
    )
    _env_marker_setting(
        name = name,
        expression = expression,
        os_name = select(os_name_select_map),
        sys_platform = select(sys_platform_select_map),
        platform_machine = select(platform_machine_select_map),
        platform_system = select(platform_system_select_map),
        platform_release = select({
            "@platforms//os:osx": "USE_OSX_VERSION_FLAG",
            "//conditions:default": "",
        }),
        **kwargs
    )

def _env_marker_setting_impl(ctx):
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
        full_version = _get_flag(ctx.attr._python_full_version_flag)
        env["python_full_version"] = full_version
        env["implementation_version"] = full_version

    # We assume cpython if the toolchain doesn't specify because it's most
    # likely to be true.
    env["implementation_name"] = runtime.implementation_name or "cpython"
    env["os_name"] = ctx.attr.os_name
    env["sys_platform"] = ctx.attr.sys_platform
    env["platform_machine"] = ctx.attr.platform_machine

    # The `platform_python_implementation` marker value is supposed to come
    # from `platform.python_implementation()`, however, PEP 421 introduced
    # `sys.implementation.name` and the `implementation_name` env marker to
    # replace it. Per the platform.python_implementation docs, there's now
    # essentially just two possible "registered" values: CPython or PyPy.
    # Rather than add a field to the toolchain, we just special case the value
    # from `sys.implementation.name` to handle the two documented values.
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
    platform_release = ctx.attr.platform_release
    if platform_release == "USE_OSX_VERSION_FLAG":
        platform_release = _get_flag(ctx.attr._pip_whl_osx_version_flag)
    env["platform_release"] = platform_release
    env["platform_system"] = ctx.attr.platform_system

    # For lack of a better option, just use an empty string for now.
    env["platform_version"] = ""

    env.update(env_aliases())

    if evaluate(ctx.attr.expression, env = env):
        value = _ENV_MARKER_TRUE
    else:
        value = _ENV_MARKER_FALSE
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
        "platform_release": attr.string(),
        "platform_system": attr.string(),
        "sys_platform": attr.string(),
        "_pip_whl_osx_version_flag": attr.label(
            default = "//python/config_settings:pip_whl_osx_version",
            providers = [[BuildSettingInfo], [config_common.FeatureFlagInfo]],
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
