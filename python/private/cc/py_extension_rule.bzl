"""Implementation of the py_extension rule."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:attributes.bzl", "COMMON_ATTRS")
load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:reexports.bzl", "BuiltinPyInfo")
load("//python/private:rule_builders.bzl", "ruleb")
load("//python/private:toolchain_types.bzl", "TARGET_TOOLCHAIN_TYPE")

def _py_extension_impl(ctx):
    pass

_MaybeBuiltinPyInfo = [[BuiltinPyInfo]] if BuiltinPyInfo != None else []

PY_EXTENSION_ATTRS = COMMON_ATTRS | {
    "srcs": lambda: attrb.LabelList(
        allow_files = True,
        doc = "The list of source files that are processed to create the target.",
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
