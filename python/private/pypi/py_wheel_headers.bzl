"""Rule for exposing C/C++ headers from an action-installed wheel library."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":py_installed_wheel_info.bzl", "PyInstalledWheelInfo")

def _py_wheel_headers_impl(ctx):
    wheel_dir = ctx.attr.wheel_library[PyInstalledWheelInfo].directory
    includes = []
    for raw_dir in ctx.attr.include_dirs:
        norm = paths.normalize(raw_dir)
        if not raw_dir or paths.is_absolute(raw_dir) or norm == ".." or norm.startswith("../"):
            fail("include_dirs entries must be non-empty relative paths within the wheel tree, got '{}'".format(raw_dir))
        includes.append(wheel_dir.path if norm == "." else wheel_dir.path + "/" + norm)

    compilation_context = cc_common.create_compilation_context(
        headers = depset([wheel_dir]),
        includes = depset(includes),
    )

    return [
        DefaultInfo(files = depset([wheel_dir])),
        CcInfo(compilation_context = compilation_context),
    ]

py_wheel_headers = rule(
    implementation = _py_wheel_headers_impl,
    provides = [CcInfo],
    doc = """Exposes C/C++ headers from an installed wheel library (TreeArtifact) as CcInfo.

Given a `py_wheel_library` target (or `@pypi//<pkg>:srcs` when `experimental_action_install`
is enabled), this rule exposes the headers at `include_dirs` within the wheel's installed
directory tree without requiring `glob()` in the repository `BUILD` file.

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
    attrs = {
        "include_dirs": attr.string_list(
            default = ["include", "site-packages"],
            doc = """
Relative paths within the installed wheel tree root (e.g. `["site-packages/numpy/_core/include"]`
or `["include/python3.12"]`) to add to the C/C++ include search path.
""",
        ),
        "wheel_library": attr.label(
            mandatory = True,
            providers = [PyInstalledWheelInfo],
            doc = """
A target providing `PyInstalledWheelInfo` (such as a `py_wheel_library` target or
`@pypi//<pkg>:srcs` when `experimental_action_install` is enabled).
""",
        ),
    },
)
