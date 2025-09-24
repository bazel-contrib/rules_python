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

    # Compile sources
    _, compilation_outputs = cc_common.compile(
        name = ctx.label.name,
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        srcs = ctx.files.srcs,
        compilation_contexts = [all_deps_cc_info.compilation_context],
    )

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

    # This function also does the linking
    _, linking_outputs = cc_common.create_linking_context_from_compilation_outputs(
        name = ctx.label.name,
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        user_link_flags = user_link_flags,
        linking_contexts = [static_linking_context, dynamic_linking_context],
    )

    print(linking_outputs)
    ltl = linking_outputs.library_to_link
    print(ltl)
    print(ltl.dynamic_library)
    print(ltl.resolved_symlink_dynamic_library)
    lib_dso = ltl.resolved_symlink_dynamic_library
    if lib_dso == None:
        lib_dso = ltl.dynamic_library

    if lib_dso == None:
        fail("No DSO output found in {}".format(ltl))

    # todo: pick appropriate infix based on py_extension attr settings
    py_dso = ctx.actions.declare_file("{}.so".format(ctx.label.name))
    ctx.actions.run_shell(
        command = 'cp "$1" "$2"',
        arguments = [lib_dso.path, py_dso.path],
        inputs = [lib_dso],
        outputs = [py_dso],
    )

    # Propagate CcInfo from dynamic and external deps, but not static ones.
    propagated_cc_info = cc_common.merge_cc_infos(
        cc_infos = dynamic_deps_infos + external_deps_infos,
    )

    return [
        DefaultInfo(
            files = depset([py_dso]),
            runfiles = ctx.runfiles([py_dso]),
        ),
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
    "srcs": lambda: attrb.LabelList(
        allow_files = True,
        doc = "The list of source files that are processed to create the target.",
    ),
    "static_deps": lambda: attrb.LabelList(
        providers = [CcInfo],
        doc = "cc_library targets to be statically and privately linked.",
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
        fragments = ["cpp"],
        **kwargs
    )
    return builder

py_extension = create_py_extension_rule_builder().build()
