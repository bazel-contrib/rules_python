"""Implementation of rules supporting py_extension.

:::{include} /_includes/experimental_api.md
:::
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:attributes.bzl", "COMMON_ATTRS", "IMPORTS_ATTRS", "WINDOWS_CONSTRAINTS_ATTRS")
load("//python/private:builders.bzl", "builders")
load("//python/private:common.bzl", "get_imports", "is_windows_platform")
load("//python/private:py_info.bzl", "PyInfo", "PyInfoBuilder")
load("//python/private:rule_builders.bzl", "ruleb")
load("//python/private:toolchain_types.bzl", "CC_TOOLCHAIN_TYPE", "PY_CC_TOOLCHAIN_TYPE")

def _py_extension_wrapper_impl(ctx):
    module_name = ctx.attr.module_name or ctx.label.name

    ext = _get_extension(ctx)
    py_toolchain = ctx.toolchains[PY_CC_TOOLCHAIN_TYPE]
    py_cc_toolchain = py_toolchain.py_cc_toolchain
    use_py_limited_api = bool(ctx.attr.py_limited_api)
    if use_py_limited_api:
        output_filename = "{module_name}.abi3.{ext}".format(
            module_name = module_name,
            ext = ext,
        )
    elif py_cc_toolchain.soabi:
        output_filename = "{module_name}.{soabi}.{ext}".format(
            module_name = module_name,
            soabi = py_cc_toolchain.soabi,
            ext = ext,
        )
    else:
        output_filename = "{module_name}.{ext}".format(
            module_name = module_name,
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

    py_info_builder = PyInfoBuilder.new()
    py_info_builder.transitive_sources.add(py_dso)
    py_info_builder.imports.add(get_imports(ctx))

    return [
        DefaultInfo(
            files = depset([py_dso]),
            runfiles = runfiles,
        ),
        py_info_builder.build(),
    ]

PY_EXTENSION_WRAPPER_ATTRS = dicts.add(
    COMMON_ATTRS,
    IMPORTS_ATTRS,
    WINDOWS_CONSTRAINTS_ATTRS,
    {
        "module_name": lambda: attrb.String(
            doc = "Custom Python module name. If not set, defaults to name.",
        ),
        "py_limited_api": lambda: attrb.String(
            default = "",
            doc = "Python limited API version string (e.g., '3.8').",
        ),
        "src": lambda: attrb.Label(
            mandatory = True,
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

def _py_extension_libs_impl(ctx):
    py_toolchain = ctx.toolchains[PY_CC_TOOLCHAIN_TYPE]
    py_cc_toolchain = py_toolchain.py_cc_toolchain
    cc_info = py_cc_toolchain.libs.providers_map["CcInfo"]
    files = []
    for input in cc_info.linking_context.linker_inputs.to_list():
        for lib in input.libraries:
            if lib.interface_library:
                files.append(lib.interface_library)
            elif lib.static_library:
                files.append(lib.static_library)
            elif lib.dynamic_library:
                files.append(lib.dynamic_library)
    link_files = [f for f in files if not f.path.endswith(".dll")]
    return [DefaultInfo(files = depset(link_files))]

py_extension_libs = rule(
    implementation = _py_extension_libs_impl,
    toolchains = [PY_CC_TOOLCHAIN_TYPE],
    doc = """\
Private internal helper rule for extracting Windows C/C++ library files from toolchain.
""",
)
