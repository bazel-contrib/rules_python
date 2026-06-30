"""Implementation of the py_extension rule."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//python:versions.bzl", "PLATFORMS")
load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:attributes.bzl", "COMMON_ATTRS")
load("//python/private:builders.bzl", "builders")
load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:py_internal.bzl", "py_internal")
load("//python/private:reexports.bzl", "BuiltinPyInfo")
load("//python/private:rule_builders.bzl", "ruleb")
load("//python/private:toolchain_types.bzl", "PY_CC_TOOLCHAIN_TYPE")

def _py_extension_impl(ctx):
    module_name = ctx.attr.module_name or ctx.label.name
    repo_name = ctx.label.workspace_name or ctx.workspace_name
    import_path = repo_name
    if ctx.label.package:
        import_path = repo_name + "/" + ctx.label.package
    cc_toolchain = ctx.toolchains["@bazel_tools//tools/cpp:toolchain_type"].cc
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )

    # Collect CcInfo from all deps for compilation
    static_deps_infos = [dep[CcInfo] for dep in ctx.attr.static_deps]
    dynamic_deps_infos = [dep[CcSharedLibraryInfo] for dep in ctx.attr.dynamic_deps]
    external_deps_infos = [dep[CcInfo] for dep in ctx.attr.external_deps]

    # Static deps are linked directly into the .so
    static_cc_info = cc_common.merge_cc_infos(
        cc_infos = static_deps_infos,
    )

    # Dynamic deps are linked as shared libraries
    linker_inputs = [dep.linker_input for dep in dynamic_deps_infos]
    dynamic_linking_context = cc_common.create_linking_context(
        linker_inputs = depset(linker_inputs),
    )

    user_link_flags = []
    user_link_flags.append("-Wl,--export-dynamic-symbol=PyInit_{module_name}".format(
        module_name = module_name,
    ))

    # The PyInit symbol looks unused, so the linker optimizes it away. Telling it
    # to treat it as undefined causes it to be retained.
    user_link_flags.append("-Wl,--undefined=PyInit_{module_name}".format(
        module_name = module_name,
    ))

    if ctx.attr.external_deps:
        user_link_flags.append("-Wl,--allow-shlib-undefined")

    ext = _get_extension(cc_toolchain)
    use_py_limited_api = bool(ctx.attr.py_limited_api)
    if use_py_limited_api:
        # check that all dependencies have compatible API versions, if defined
        _check_limited_api_compatibility(ctx, ctx.attr.py_limited_api)

        output_filename = "{module_name}.abi3.{ext}".format(
            module_name=module_name,
            ext=ext,
        )
    else:
        py_toolchain = ctx.toolchains[PY_CC_TOOLCHAIN_TYPE]
        py_cc_toolchain = py_toolchain.py_cc_toolchain
        platform_tag = _get_platform(ctx, cc_toolchain)
        output_filename = "{module_name}.{abi_tag}-{platform}.{ext}".format(
            module_name = module_name,
            abi_tag = py_cc_toolchain.abi_tag,
            platform = platform_tag,
            ext = ext,
        )
    py_dso = ctx.actions.declare_file(output_filename)

    static_linking_context = static_cc_info.linking_context
    linking_contexts = [
        static_linking_context,
        dynamic_linking_context,
    ]

    # Add target-level linkopts last so users can override.
    user_link_flags.extend(ctx.attr.linkopts)
    print((
        "===LINK:\n" +
        "  user_link_flags={user_link_flags}"
    ).format(
        user_link_flags = user_link_flags,
    ))

    # todo: add linker script to hide symbols by default
    # py_internal allows using some private apis, which may or may not be needed.
    # based upon cc_shared_library.bzl
    cc_linking_outputs = py_internal.link(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        linking_contexts = linking_contexts,
        user_link_flags = user_link_flags,
        # todo: add additional_inputs
        name = ctx.label.name,
        output_type = "dynamic_library",
        main_output = py_dso,
        # todo: maybe variables_extension
        # todo: maybe additional_outputs
    )
    print((
        "===LINK OUTPUT:\n" +
        "  {}"
    ).format(
        cc_linking_outputs,
    ))

    # Propagate CcInfo from dynamic and external deps, but not static ones.
    dynamic_cc_info = CcInfo(linking_context = dynamic_linking_context)
    propagated_cc_info = cc_common.merge_cc_infos(
        cc_infos = [dynamic_cc_info] + external_deps_infos,
    )

    runfiles_builder = builders.RunfilesBuilder()
    runfiles_builder.add(py_dso)
    runfiles_builder.add_targets(ctx.attr.static_deps)
    runfiles_builder.add_targets(ctx.attr.dynamic_deps)
    runfiles_builder.add_targets(ctx.attr.external_deps)
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
        propagated_cc_info,
    ]

_MaybeBuiltinPyInfo = [[BuiltinPyInfo]] if BuiltinPyInfo != None else []

PY_EXTENSION_ATTRS = COMMON_ATTRS | {
    "dynamic_deps": lambda: attrb.LabelList(
        providers = [CcSharedLibraryInfo],
        doc = "cc_shared_library targets to be dynamically linked.",
        default = [],
    ),
    "external_deps": lambda: attrb.LabelList(
        providers = [CcInfo],
        doc = "cc_library targets with external linkage.",
        default = [],
    ),
    "static_deps": lambda: attrb.LabelList(
        providers = [CcInfo],
        doc = "cc_library targets to be statically and privately linked.",
        default = [],
    ),
    "copts": lambda: attrb.StringList(),
    "linkopts": lambda: attrb.StringList(),
    "module_name": lambda: attrb.String(),
    "py_limited_api": lambda: attrb.String(
        doc = """
The minimum Python version to target for the Limited API (e.g., '3.8').

If set to a version string (e.g., '3.8') instead of '' (empty string):
  - Configures the output filename to use the simple '.abi3' suffix
    (e.g., 'ext.abi3.so').
  - Strictly validates that all linked C++ dependencies (static_deps,
    dynamic_deps, etc.) are binary-compatible with this target version,
    failing the build if a dependency is missing the 'Py_LIMITED_API'
    define or targets a newer version.

Note: Since the py_extension rule only links pre-compiled libraries,
you must manually add the preprocessor macro to the cc_library targets
that compile your C/C++ sources, for example:
    cc_library(
        name = "my_impl",
        srcs = ["my_code.c"],
        defines = ["Py_LIMITED_API=0x03080000"],
        ...
    )

Set to '' (the default) or None to build a standard, version-specific
extension.
""",
        default = ""
    ),
    "_constraints": lambda: attrb.LabelList(
        default = [
            "@platforms//os:linux",
            "@platforms//os:macos",
            "@platforms//os:windows",
            "@platforms//cpu:x86_64",
            "@platforms//cpu:aarch64",
            "@platforms//cpu:armv7",
            "@platforms//cpu:i386",
            "@platforms//cpu:ppc",
            "@platforms//cpu:riscv64",
            "@platforms//cpu:s390x",
        ],
    ),
}

def create_py_extension_rule_builder(**kwargs):
    """Create a rule builder for a py_extension."""
    builder = ruleb.Rule(
        implementation = _py_extension_impl,
        attrs = PY_EXTENSION_ATTRS,
        provides = [PyInfo, CcInfo],
        toolchains = [
            ruleb.ToolchainType(PY_CC_TOOLCHAIN_TYPE),
            ruleb.ToolchainType("@bazel_tools//tools/cpp:toolchain_type"),
        ],
        fragments = ["cpp"],
        **kwargs
    )
    return builder

py_extension = create_py_extension_rule_builder().build()

# Map Bazel's internal CPU names to PEP 3149 standard architecture names
_BAZEL_CPU_TO_PEP_ARCH = {
    "k8": "x86_64",
    "amd64": "x86_64",
    "x86_64": "x86_64",
    "aarch64": "aarch64",
    "arm64": "arm64",
    "darwin": "x86_64",       # Historical Bazel Mac CPU
    "darwin_x86_64": "x86_64",
    "darwin_arm64": "arm64",
    "x64_windows": "x86_64",
    "arm64_windows": "arm64",
}

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
            return _derive_pep3149_tag(platform, info)

    return None

def _get_platform(ctx, cc_toolchain):
    """Derives the PEP 3149 platform tag from the C++ toolchain or target constraints.

    Args:
        ctx: The rule context.
        cc_toolchain: The CcToolchainInfo provider (usually obtained via
          ctx.toolchains["@bazel_tools//tools/cpp:toolchain_type"].cc)

    Returns:
        The platform tag, e.g. "x86_64-linux-gnu" or "win_amd64"
    """
    # Try to resolve using modern platform constraints and PLATFORMS
    platform_tag = _get_platform_from_constraints(ctx)
    if platform_tag:
        return platform_tag

    # Fallback to legacy cc_toolchain parsing
    # Get the GNU target name (e.g., "local-linux-gnu" or "x86_64-unknown-linux-gnu")
    target_name = cc_toolchain.target_gnu_system_name

    # Detect the OS family
    is_windows = "windows" in target_name or "mingw" in target_name or "msvc" in target_name
    is_mac = "apple" in target_name or "darwin" in target_name

    # Parse the architecture from the target_name
    # e.g., "x86_64-unknown-linux-gnu" -> "x86_64"
    target_parts = target_name.split("-")
    arch = target_parts[0]

    # Handle the "local" placeholder by falling back to cc_toolchain.cpu
    if arch == "local":
        cpu = cc_toolchain.cpu
        # Resolve the Bazel CPU name to a standard PEP architecture
        arch = _BAZEL_CPU_TO_PEP_ARCH.get(cpu, cpu)
    # Normalize standard names if they came from a full target_name
    elif arch == "amd64":
        arch = "x86_64"
    elif arch == "aarch64":
        arch = "arm64" if is_mac else "aarch64"

    # Derive the PEP 3149 / PEP 425 platform tag
    if is_windows:
        platform_tag = "win_amd64" if arch == "x86_64" else "win32"
    elif is_mac:
        platform_tag = "darwin"
    else:
        # Linux/Unix: Reconstruct the triplet, dropping the vendor if present
        os_part = "linux"
        abi_part = "gnu"

        if len(target_parts) == 4:
            # [arch, vendor, os, abi]
            os_part = target_parts[2]
            abi_part = target_parts[3]
        elif len(target_parts) == 3:
            # [arch, os, abi]
            os_part = target_parts[1]
            abi_part = target_parts[2]

        platform_tag = "{}-{}-{}".format(arch, os_part, abi_part)

    return platform_tag


def _version_to_hex(version_str):
    """Converts a version string like '3.10' to Python's version hex '0x030a0000'."""
    parts = version_str.split(".")
    if len(parts) != 2:
        fail("Invalid py_limited_api version '{}', expected 'major.minor' format (e.g., '3.8')".format(version_str))

    major = int(parts[0])
    minor = int(parts[1])

    if major != 3:
        fail("Python Limited API is only supported for Python 3.2+ (got Python {})".format(major))
    if minor < 2:
        fail("Python Limited API is only supported for Python 3.2+ (got 3.{})".format(minor))

    # Format the minor version as a 2-digit hex (e.g., 10 -> "0a")
    # Starlark doesn't seem to support %02x formatting

    return "0x03%x%x0000" % (minor//16, minor%16)


def _check_limited_api_compatibility(ctx, ext_version_str):
    """Validates that all C++ dependencies are binary-compatible with the extension's Limited API target."""
    if not ext_version_str:
        return

    ext_version_hex = _version_to_hex(ext_version_str)
    ext_version_val = int(ext_version_hex, 16)

    # Collect all dependencies that might propagate CcInfo
    deps = []
    deps.extend(ctx.attr.static_deps)
    deps.extend(ctx.attr.dynamic_deps)
    deps.extend(ctx.attr.external_deps)

    for dep in deps:
        if CcInfo not in dep:
            continue

        comp_ctx = dep[CcInfo].compilation_context

        # Detect if the dependency has access to Python headers
        has_python_headers = False
        for header in comp_ctx.headers.to_list():
            if header.basename == "Python.h":
                has_python_headers = True
                break

        # Inspect the propagated defines
        has_limited_api_define = False
        limited_api_define_value = None

        for define in comp_ctx.defines.to_list():
            if define.startswith("Py_LIMITED_API="):
                has_limited_api_define = True
                limited_api_define_value = define.split("=")[1]
            elif define == "Py_LIMITED_API":
                has_limited_api_define = True
                limited_api_define_value = "unspecified"

        # Enforce the compatibility contract

        # Contract Rule A: If the library uses Python, it MUST use the Limited API
        if has_python_headers and not has_limited_api_define:
            fail((
                "\nERROR: Unsafe Python C API usage in dependency:\n" +
                "  Dependency '{dep}' includes Python headers (contains 'Python.h')\n" +
                "  but does NOT define 'Py_LIMITED_API'.\n" +
                "  This will link unstable Python symbols into your Stable ABI extension.\n" +
                "  Please add: defines = [\"Py_LIMITED_API={ext_hex}\"] to '{dep}'."
            ).format(
                dep = dep.label,
                ext_hex = ext_version_hex,
            ))

        # Contract Rule B: If the Limited API is defined, it must be version-safe
        if has_limited_api_define:
            if limited_api_define_value == "unspecified":
                fail((
                    "\nERROR: Unsafe Python Limited API definition in dependency\n" +
                    "  Dependency '{dep}' defines 'Py_LIMITED_API' without a version hex.\n" +
                    "  Please change it to specify the target version explicitly, " +
                    "for example: defines = [\"Py_LIMITED_API={ext_hex}\"]"
                ).format(
                    dep = dep.label,
                    ext_hex = ext_version_hex,
                ))
            else:
                dep_version_val = int(limited_api_define_value.rstrip("ULul"), 16)
                if dep_version_val > ext_version_val:
                    fail((
                        "\nERROR: Incompatible Python Limited API targets detected\n" +
                        "  Extension '{self}' targets version '{ext_ver}' ({ext_hex}).\n" +
                        "  Dependency '{dep}' targets a NEWER version ({dep_hex}).\n" +
                        "  You cannot link a newer Limited API library into an older extension."
                    ).format(
                        self = ctx.label,
                        ext_ver = ext_version_str,
                        ext_hex = ext_version_hex,
                        dep = dep.label,
                        dep_hex = limited_api_define_value,
            ))
