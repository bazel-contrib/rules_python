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
        csl_target[CcSharedLibraryInfo],
    ]

PY_EXTENSION_WRAPPER_ATTRS = COMMON_ATTRS | {
    "src": lambda: attrb.Label(
        mandatory = True,
        providers = [CcSharedLibraryInfo],
        doc = "The cc_shared_library target to wrap.",
    ),
    "libc": lambda: attrb.String(default = "glibc"),
    "module_name": lambda: attrb.String(),
    "py_limited_api": lambda: attrb.String(
        default = "",
    ),
    "_constraints": lambda: attrb.LabelList(
        default = sorted({
            c: None
            for info in PLATFORMS.values()
            for c in info.compatible_with
        }.keys()),
    ),
}

def create_py_extension_wrapper_rule_builder(**kwargs):
    """Create a rule builder for the wrapper."""
    builder = ruleb.Rule(
        implementation = _py_extension_wrapper_impl,
        attrs = PY_EXTENSION_WRAPPER_ATTRS,
        provides = [PyInfo, CcSharedLibraryInfo],
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

def _derive_pep3149_tag(platform, info):
    # platform is the triplet, e.g. "x86_64-unknown-linux-gnu"
    p, _, _ = platform.partition("-freethreaded")
    parts = p.split("-")
    triplet_arch = parts[0]

    if info.os_name == "windows":
        if triplet_arch == "x86_64":
            return "win_amd64"
        elif triplet_arch == "aarch64":
            return "win_arm64"
        else:
            return "win32"
    elif info.os_name == "osx":
        return "darwin"
    elif info.os_name == "linux":
        abi = "musl" if p.endswith("-musl") else "gnu"
        return "{}-linux-{}".format(triplet_arch, abi)
    else:
        return triplet_arch

def _get_platform_from_constraints(ctx):
    # Build a map of Label to ConstraintValueInfo from _constraints
    constraints_map = {}
    for c in ctx.attr._constraints:
        if platform_common.ConstraintValueInfo in c:
            constraints_map[c.label] = c[platform_common.ConstraintValueInfo]

    # Resolve the target's libc to its config_setting label string
    target_libc_setting = None
    if ctx.attr.libc == "musl":
        target_libc_setting = str(Label("//python/config_settings:_is_py_linux_libc_musl"))
    elif ctx.attr.libc == "glibc":
        target_libc_setting = str(Label("//python/config_settings:_is_py_linux_libc_glibc"))

    # Find the matching platform in PLATFORMS
    for platform, info in PLATFORMS.items():
        # Check if all compatible_with constraints are satisfied
        match = True
        for c_str in info.compatible_with:
            c_label = Label(c_str)
            if c_label in constraints_map:
                c_val = constraints_map[c_label]
                if not ctx.target_platform_has_constraint(c_val):
                    match = False
                    break
            else:
                match = False
                break

        if match:
            # Additional check for Linux libc consistency using target_settings
            if info.os_name == "linux" and target_libc_setting:
                if target_libc_setting not in info.target_settings:
                    match = False

        if match:
            return _derive_pep3149_tag(platform, info)

    return None

def _get_platform(ctx):
    """Derives the PEP 3149 platform tag from the target constraints.

    Args:
        ctx: The rule context.

    Returns:
        The platform tag, e.g. "x86_64-linux-gnu" or "win_amd64"
    """
    platform_tag = _get_platform_from_constraints(ctx)
    if platform_tag:
        return platform_tag

    fail(
        """
ERROR: Unsupported target platform for {self}.
  The target platform's constraints do not match any supported platform
  in rules_python's central registry (python/versions.bzl).
  Please ensure your target platform is configured correctly.""".format(
            self = ctx.label,
        ),
    )
