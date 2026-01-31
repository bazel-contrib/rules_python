load("//python/private:toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")

_WHEEL_TAGS_TRUE = "TRUE"
_WHEEL_TAGS_FALSE = "FALSE"

def wheel_tags_setting(*, name, **wheel_tags):
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
            ":{}".format(name): _WHEEL_TAGS_TRUE,
        },
    )
    _wheel_tags_setting(
        name = name,
        os = select({
            "@platforms//os:linux": "linux",
            "//conditions:default": "other",
        }),
        arch = select({
            "@platforms//cpu:x86_64": "x86",
            "//conditions:default": "other",
        }),
        **wheel_tags
    )

def _wheel_tags_setting_impl(ctx):
    runtime = ctx.toolchains[TARGET_TOOLCHAIN_TYPE].py3_runtime

    pyimpl_is_compatible = False
    abi_is_compatible = False
    platform_is_compatible = False

    python_tag = ctx.attr.python_tag
    if python_tag in ("py3", "any"):
        pyimpl_is_compatible = True
    elif python_tag.startswith("cp"):
        ptv = python_tag[2:]
        major = runtime.interpreter_version_info.major
        minor = runtime.interpreter_version_info.minor
        mm = "{}{}".format(major, minor)
        pyimpl_is_compatible = mm == ptv
    else:
        pass

    abi_tag = ctx.attr.abi_tag
    if abi_tag == "none":
        abi_is_compatible = True
    elif abi_tag.startswith("cp"):
        abv = abi_tag[2:]
        major = runtime.interpreter_version_info.major
        minor = runtime.interpreter_version_info.minor
        mm = "{}{}".format(major, minor)
        abi_is_compatible = mm == abv
    else:
        pass

    """
    (musl|many)linux_arch
    """
    platform_tag = ctx.attr.platform_tag
    if platform_tag == "any":
        platform_is_compatible = True
    else:
        libc = "musl" if musl in platform_tag else "glibc"
        if "linux" in platform_tag:
            os = "linux"
        else:
            os = "other"
        if "x86" in platform_tag:
            arch = "x86"
        elif "arm64" in platform_tag or "aarch64" in platform_tag:
            arch = "arm"
        else:
            arch = "other"

        platform_is_compatible = (
            os == ctx.attr.os and
            arch == ctx.attr.arch and
            libc == ctx.attr._libc[config_common.FeatureFlagInfo].value
        )

    compatible = (pyimpl_is_compatible and
                  abi_is_compatible and
                  platform_is_compatible)
    value = "TRUE" if compatible else "FALSE"
    return [config_common.FeatureFlagInfo(value = value)]

_wheel_tags_setting = rule(
    implementation = _wheel_tags_setting_impl,
    attrs = {
        "python_tag": attr.string(),
        "abi_tag": attr.string(),
        "platform_tag": attr.string(),
        "_libc": attr.label(
            default = "//python/config_settings:py_linux_libc",
        ),
    },
    toolchains = [
        config_common.toolchain_type(
            TARGET_TOOLCHAIN_TYPE,
            mandatory = False,
        ),
    ],
)
