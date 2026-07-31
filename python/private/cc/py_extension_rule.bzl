"""Implementation of rules supporting py_extension.

:::{include} /_includes/experimental_api.md
:::
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@rules_cc//cc/common:cc_shared_library_info.bzl", "CcSharedLibraryInfo")
load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:attributes.bzl", "COMMON_ATTRS", "IMPORTS_ATTRS", "WINDOWS_CONSTRAINTS_ATTRS")
load("//python/private:builders.bzl", "builders")
load("//python/private:common.bzl", "get_imports", "is_windows_platform")
load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:rule_builders.bzl", "ruleb")
load("//python/private:toolchain_types.bzl", "CC_TOOLCHAIN_TYPE", "PY_CC_TOOLCHAIN_TYPE")

def _py_extension_wrapper_impl(ctx):
    module_name = ctx.attr.module_name or ctx.label.name

    ext = _get_extension(ctx)
    use_py_limited_api = bool(ctx.attr.py_limited_api)
    if use_py_limited_api:
        output_filename = "{module_name}.abi3.{ext}".format(
            module_name = module_name,
            ext = ext,
        )
    else:
        py_toolchain = ctx.toolchains[PY_CC_TOOLCHAIN_TYPE]
        py_cc_toolchain = py_toolchain.py_cc_toolchain
        platform_tag = _get_platform(ctx)
        output_filename = "{module_name}.{abi_tag}-{platform}.{ext}".format(
            module_name = module_name,
            abi_tag = py_cc_toolchain.abi_tag,
            platform = platform_tag,
            ext = ext,
        )

    py_dso = ctx.actions.declare_file(output_filename)

    # Symlink the cc_shared_library output to the PEP 3149 / abi3 filename
    csl_target = ctx.attr.src
    csl_file = csl_target[DefaultInfo].files.to_list()[0]
    ctx.actions.symlink(
        output = py_dso,
        target_file = csl_file,
    )

    runfiles_builder = builders.RunfilesBuilder()
    runfiles_builder.add(py_dso)
    runfiles_builder.add(ctx.files.data)
    runfiles_builder.add_targets(ctx.attr.data)
    runfiles_builder.add(csl_target[DefaultInfo].default_runfiles)
    runfiles = runfiles_builder.build(ctx)

    return [
        DefaultInfo(
            files = depset([py_dso]),
            runfiles = runfiles,
        ),
        PyInfo(
            transitive_sources = depset([py_dso]),
            imports = depset(get_imports(ctx)),
        ),
    ]

PY_EXTENSION_WRAPPER_ATTRS = dicts.add(
    COMMON_ATTRS,
    IMPORTS_ATTRS,
    WINDOWS_CONSTRAINTS_ATTRS,
    {
        "libc": lambda: attrb.String(
            default = "glibc",
            doc = "Target C library variant (e.g., glibc, musl).",
        ),
        "module_name": lambda: attrb.String(
            doc = "Custom Python module name. If not set, defaults to name.",
        ),
        "py_limited_api": lambda: attrb.String(
            default = "",
            doc = "Python limited API version string (e.g., '3.8').",
        ),
        "src": lambda: attrb.Label(
            mandatory = True,
            providers = [CcSharedLibraryInfo],
            doc = "The cc_shared_library target to wrap.",
        ),
    },
)

def create_py_extension_wrapper_rule_builder():
    """Create a rule builder for the private internal wrapper rule."""
    return ruleb.Rule(
        doc = "Private internal helper rule for py_extension targets.",
        implementation = _py_extension_wrapper_impl,
        attrs = PY_EXTENSION_WRAPPER_ATTRS,
        provides = [PyInfo],
        toolchains = [
            ruleb.ToolchainType(PY_CC_TOOLCHAIN_TYPE),
            ruleb.ToolchainType(CC_TOOLCHAIN_TYPE),
        ],
        fragments = ["cpp"],
    )

py_extension_wrapper = create_py_extension_wrapper_rule_builder().build()

def _get_extension(ctx):
    """Derives the appropriate file extension for C extensions from target platform.

    Note: On macOS, CPython C extensions use .so (PEP 3149), not .dylib.
    Windows uses .pyd.

    Args:
        ctx: The rule context.

    Returns:
        The extension, e.g. "so" or "pyd"
    """
    return "pyd" if is_windows_platform(ctx) else "so"

def _get_platform(ctx):
    """Derives the PEP 3149 platform tag from the active Python C++ toolchain.

    Args:
        ctx: The rule context.

    Returns:
        The platform tag, e.g. "x86_64-linux-gnu" or "win_amd64"
    """
    py_toolchain = ctx.toolchains[PY_CC_TOOLCHAIN_TYPE]
    py_cc_toolchain = py_toolchain.py_cc_toolchain
    if not py_cc_toolchain.platform_tag:
        fail(
            "ERROR: Unable to resolve platform_tag from Python C++ toolchain for {self}. " +
            "Please ensure the active py_cc_toolchain provides a non-empty platform_tag.",
        )
    return py_cc_toolchain.platform_tag
