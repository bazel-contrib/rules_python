"""Implementation of the py_extension rule."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:attributes.bzl", "COMMON_ATTRS")
load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:reexports.bzl", "BuiltinPyInfo")
load("//python/private:rule_builders.bzl", "ruleb")
load("//python/private:toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")

def _py_extension_impl(ctx):
    cc_toolchain = cc_common.get_toolchain_info(ctx = ctx).cc_toolchain
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

    # Compile sources
    compilation_outputs, _ = cc_common.compile(
        name = ctx.label.name,
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        srcs = ctx.files.srcs,
        compilation_context = all_deps_cc_info.compilation_context,
    )

    # Link the extension
    output_filename = ctx.label.name + ".so"
    output = ctx.actions.declare_file(output_filename)

    # Static deps are linked directly into the .so
    static_linking_context = cc_common.merge_cc_infos(
        cc_infos = static_deps_infos,
    ).linking_context

    # Dynamic deps are linked as shared libraries
    dynamic_linking_context = cc_common.merge_cc_infos(
        cc_infos = dynamic_deps_infos,
    ).linking_context

    # For external deps, we need to allow undefined symbols.
    user_link_flags = []
    if ctx.attr.external_deps:
        user_link_flags.append("-Wl,--allow-shlib-undefined")

    cc_common.link(
        name = ctx.label.name,
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        output = output,
        linking_contexts = depset([static_linking_context, dynamic_linking_context]),
        linker_inputs = depset([compilation_outputs.linker_inputs]),
        output_type = "dynamic_library",
        user_link_flags = user_link_flags,
        neverlink = True,
    )

    # Propagate CcInfo from dynamic and external deps, but not static ones.
    propagated_cc_info = cc_common.merge_cc_infos(
        cc_infos = dynamic_deps_infos + external_deps_infos,
    )

    return [
        DefaultInfo(files = depset([output])),
        PyInfo(
            transitive_sources = depset([output]),
        ),
        propagated_cc_info,
    ]

_MaybeBuiltinPyInfo = [[BuiltinPyInfo]] if BuiltinPyInfo != None else []

PY_EXTENSION_ATTRS = COMMON_ATTRS | {
    "srcs": lambda: attrb.LabelList(
        allow_files = True,
        doc = "The list of source files that are processed to create the target.",
    ),
    "static_deps": lambda: attrb.LabelList(
        providers = [CcInfo],
        doc = "cc_library targets to be statically and privately linked.",
        default = [],
    ),
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
        **kwargs
    )
    return builder

py_extension = create_py_extension_rule_builder().build()
