"""Implementation of the py_extension rule."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:attributes.bzl", "COMMON_ATTRS")
load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:py_internal.bzl", "py_internal")
load("//python/private:reexports.bzl", "BuiltinPyInfo")
load("//python/private:rule_builders.bzl", "ruleb")
load("//python/private:toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")

def _py_extension_impl(ctx):
    module_name = ctx.attr.module_name or ctx.label.name
    cc_toolchain = ctx.toolchains["@bazel_tools//tools/cpp:toolchain_type"].cc
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )

    # Collect CcInfo from all deps for compilation
    static_deps_infos = [dep[CcInfo] for dep in ctx.attr.static_deps]
    dynamic_deps_infos = [dep[CcInfo] for dep in ctx.attr.dynamic_deps]
    external_deps_infos = [dep[CcInfo] for dep in ctx.attr.external_deps]
    all_deps_cc_info = cc_common.merge_cc_infos(
        cc_infos = static_deps_infos + dynamic_deps_infos + external_deps_infos,
    )

    # Static deps are linked directly into the .so
    static_cc_info = cc_common.merge_cc_infos(
        cc_infos = static_deps_infos,
    )

    # Dynamic deps are linked as shared libraries
    dynamic_linking_context = cc_common.merge_cc_infos(
        cc_infos = dynamic_deps_infos,
    ).linking_context

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

    # todo: use toolchain to determine `abi3.` infix
    # todo: use toolchain to determine platform extension (pyd, so, etc)
    output_filename = "{module_name}.{ext}".format(
        module_name = module_name,
        ext = "so",
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
    propagated_cc_info = cc_common.merge_cc_infos(
        cc_infos = dynamic_deps_infos + external_deps_infos,
    )

    return [
        DefaultInfo(files = depset([py_dso])),
        PyInfo(
            transitive_sources = depset([py_dso]),
        ),
        propagated_cc_info,
    ]

_MaybeBuiltinPyInfo = [[BuiltinPyInfo]] if BuiltinPyInfo != None else []

PY_EXTENSION_ATTRS = COMMON_ATTRS | {
    "dynamic_deps": lambda: attrb.LabelList(
        providers = [CcInfo],
        doc = "cc_library targets to be dynamically linked.",
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
}

def create_py_extension_rule_builder(**kwargs):
    """Create a rule builder for a py_extension."""
    builder = ruleb.Rule(
        implementation = _py_extension_impl,
        attrs = PY_EXTENSION_ATTRS,
        provides = [PyInfo, CcInfo],
        toolchains = [
            ruleb.ToolchainType(TARGET_TOOLCHAIN_TYPE),
            ruleb.ToolchainType("@bazel_tools//tools/cpp:toolchain_type"),
        ],
        fragments = ["cpp"],
        **kwargs
    )
    return builder

py_extension = create_py_extension_rule_builder().build()
