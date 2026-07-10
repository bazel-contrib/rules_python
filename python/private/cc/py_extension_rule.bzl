"""Implementation of the _py_extension_wrapper rule."""

load("@rules_cc//cc/common:cc_shared_library_info.bzl", "CcSharedLibraryInfo")
load("//python:versions.bzl", "PLATFORMS")
load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:attributes.bzl", "COMMON_ATTRS")
load("//python/private:builders.bzl", "builders")
load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:rule_builders.bzl", "ruleb")
load("//python/private:toolchain_types.bzl", "PY_CC_TOOLCHAIN_TYPE")

def _py_extension_wrapper_impl(ctx):
    module_name = ctx.attr.module_name or ctx.label.name
    repo_name = ctx.label.workspace_name or ctx.workspace_name
    import_path = repo_name
    if ctx.label.package:
        import_path = repo_name + "/" + ctx.label.package

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

    return [
        DefaultInfo(
            files = depset([py_dso]),
            runfiles = runfiles,
        ),
        PyInfo(
            transitive_sources = depset([py_dso]),
            imports = depset([import_path]),
        ),
    ]

PY_EXTENSION_WRAPPER_ATTRS = COMMON_ATTRS | {
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
    "os": lambda: attrb.String(doc = "OS determined by macro select."),
    "cpu": lambda: attrb.String(doc = "CPU determined by macro select."),
}

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
    """Derives the PEP 3149 platform tag from the target constraints.
    Linux platform tags are standardized here:
      - https://peps.python.org/pep-3149/
    Windows platform tags, such as they are, are defined in this issue and
            commit (treated as a de facto standard):
      - https://github.com/python/cpython/issues/67169
      - https://github.com/python/cpython/commit/03a144bb6ac3d7631a3bdb895e2a1f2d021fb08b
    Apple platform tag is always just "darwin", discussed briefly here:
      - https://github.com/python/cpython/commit/3b8124884c3655b4cf2629d741b18c1a38181805

    Args:
        ctx: The rule context.

    Returns:
        The platform tag, e.g. "x86_64-linux-gnu" or "win_amd64"
    """
    os = ctx.attr.os
    cpu = ctx.attr.cpu

    if os == "windows":
        if cpu == "x86_64":
            return "win_amd64"
        if cpu == "aarch64":
            return "win_arm64"
        return "win32"
    if os == "macos":
        return "darwin"
    if os == "linux":
        libc = "gnu"
        if ctx.attr.libc == "musl":
            libc = "musl"
        return '{}-{}-{}'.format(cpu, os, libc)

    fail(
        """
ERROR: Unsupported target platform for {self}.
  The target platform's constraints do not match any supported platform
  in rules_python's central registry (python/versions.bzl).
  Please ensure your target platform is configured correctly.""".format(
            self = ctx.label,
        ),
    )
