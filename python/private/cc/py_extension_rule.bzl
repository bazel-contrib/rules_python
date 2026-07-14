"""Implementation of the _py_extension_wrapper rule."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@rules_cc//cc/common:cc_shared_library_info.bzl", "CcSharedLibraryInfo")
load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:attributes.bzl", "COMMON_ATTRS", "IMPORTS_ATTRS")
load("//python/private:builders.bzl", "builders")
load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:rule_builders.bzl", "ruleb")
load("//python/private:toolchain_types.bzl", "PY_CC_TOOLCHAIN_TYPE")

def _py_extension_wrapper_impl(ctx):
    module_name = ctx.attr.module_name or ctx.label.name

    cc_toolchain = ctx.toolchains["@bazel_tools//tools/cpp:toolchain_type"].cc
    ext = _get_extension(cc_toolchain)
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

    # Resolve imports paths relative to the target package and repository:
    # 1. Default (imports = []): No extra search paths are added to sys.path,
    #    enforcing clean package-qualified imports (e.g. `from foo.bar import ext`).
    # 2. Relative paths (e.g. imports = ["."]): Resolved relative to `repo_name/package_name`
    #    so passing `imports = ["."]` adds the target's package directory to sys.path.
    # 3. Absolute paths (starting with "/"): Stripped of leading "/" and resolved relative to runfiles root.
    imports_list = []
    repo_name = ctx.label.workspace_name or ctx.workspace_name
    for path in ctx.attr.imports:
        if path.startswith("/"):
            imports_list.append(path[1:])
        else:
            pkg = ctx.label.package
            full_path = "{}/{}".format(pkg, path) if pkg else path
            if repo_name:
                full_path = "{}/{}".format(repo_name, full_path)
            imports_list.append(full_path)

    return [
        DefaultInfo(
            files = depset([py_dso]),
            runfiles = runfiles,
        ),
        PyInfo(
            transitive_sources = depset([py_dso]),
            imports = depset(imports_list),
        ),
    ]

PY_EXTENSION_WRAPPER_ATTRS = dicts.add(
    COMMON_ATTRS,
    IMPORTS_ATTRS,
    {
        "libc": lambda: attrb.String(default = "glibc"),
        "module_name": lambda: attrb.String(),
        "py_limited_api": lambda: attrb.String(
            default = "",
        ),
        "src": lambda: attrb.Label(
            mandatory = True,
            providers = [CcSharedLibraryInfo],
            doc = "The cc_shared_library target to wrap.",
        ),
    },
)

def create_py_extension_wrapper_rule_builder(**kwargs):
    """Create a rule builder for the wrapper."""
    builder = ruleb.Rule(
        implementation = _py_extension_wrapper_impl,
        attrs = PY_EXTENSION_WRAPPER_ATTRS,
        provides = [PyInfo],
        toolchains = [
            ruleb.ToolchainType(PY_CC_TOOLCHAIN_TYPE),
            ruleb.ToolchainType("@bazel_tools//tools/cpp:toolchain_type"),
        ],
        fragments = ["cpp"],
        **kwargs
    )
    return builder

py_extension_wrapper = create_py_extension_wrapper_rule_builder().build()

def _get_extension(cc_toolchain):
    """
    Derives the appropriate file extension from the C++ toolchain.

    Args:
        cc_toolchain: The CcToolchainInfo provider (usually obtained via
          ctx.toolchains["@bazel_tools//tools/cpp:toolchain_type"].cc)

    Returns:
        The extension, e.g. "so" or "pyd"
    """

    # Windows uses .pyd; Unix (Linux/macOS) uses .so for Python modules
    target_name = cc_toolchain.target_gnu_system_name
    is_windows = "windows" in target_name or "mingw" in target_name or "msvc" in target_name
    ext = "pyd" if is_windows else "so"
    return ext

def _get_platform(ctx):
    """Derives the PEP 3149 platform tag from the active Python C++ toolchain.

    Args:
        ctx: The rule context.

    Returns:
        The platform tag, e.g. "x86_64-linux-gnu" or "win_amd64"
    """
    py_toolchain = ctx.toolchains[PY_CC_TOOLCHAIN_TYPE]
    py_cc_toolchain = py_toolchain.py_cc_toolchain
    if hasattr(py_cc_toolchain, "platform_tag") and py_cc_toolchain.platform_tag:
        return py_cc_toolchain.platform_tag

    fail(
        "ERROR: Unable to resolve platform_tag from Python C++ toolchain for {self}. " +
        "Please ensure the active py_cc_toolchain provides a non-empty platform_tag.",
    )
