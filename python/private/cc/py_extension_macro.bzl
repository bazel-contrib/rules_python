"""Macro for creating Python extensions."""

load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_shared_library.bzl", "cc_shared_library")
load("//python/private:util.bzl", "add_tag")
load(":py_extension_rule.bzl", "py_extension_wrapper")

def py_extension(
        name,
        srcs = None,
        hdrs = None,
        copts = None,
        defines = None,
        deps = None,
        dynamic_deps = None,
        exports_filter = None,
        user_link_flags = None,
        visibility = None,
        **kwargs):
    """Creates a Python extension module.

    Args:
        name: Target name.
        srcs: Optional C/C++ source files to compile directly for this extension.
        hdrs: Optional header files for the srcs.
        copts: Optional compiler flags for srcs.
        defines: Optional preprocessor defines for srcs.
        deps: cc_library targets to statically link into the extension.
        dynamic_deps: cc_shared_library targets to dynamically link.
        exports_filter: Filter for exported symbols passed to cc_shared_library.
        user_link_flags: Additional link flags passed to cc_shared_library.
        visibility: Target visibility.
        data: Optional list of files or targets needed by this extension at runtime.
        **kwargs: Additional arguments passed to the underlying wrapper rule.
    """
    add_tag(kwargs, "@rules_python//python/cc:py_extension")

    csl_deps = []

    # 1. Handle user-supplied static deps
    if deps:
        csl_deps.extend(deps)

    # 2. If srcs or hdrs are specified, create an implicit cc_library for them
    if srcs or hdrs:
        impl_lib_name = "_" + name + "_impl"
        cc_library(
            name = impl_lib_name,
            srcs = srcs,
            hdrs = hdrs,
            copts = (copts or []) + ["-fPIC"],
            defines = defines,
            deps = ["@rules_python//python/cc:current_py_cc_headers"],
            visibility = ["//visibility:private"],
        )
        csl_deps.append(":" + impl_lib_name)

    # 3. If no static deps or sources were specified, use empty target for CSL requirement
    if not csl_deps:
        csl_deps.append("//python/private/cc:empty")

    # 4. Create the underlying cc_shared_library
    csl_name = "_" + name + "_csl"
    csl_kwargs = {}
    if exports_filter:
        csl_kwargs["exports_filter"] = exports_filter
    if user_link_flags:
        csl_kwargs["user_link_flags"] = user_link_flags

    cc_shared_library(
        name = csl_name,
        deps = csl_deps,
        dynamic_deps = dynamic_deps,
        visibility = ["//visibility:private"],
        **csl_kwargs
    )

    # 5. Select default libc constraint if not provided
    if "libc" not in kwargs:
        kwargs["libc"] = select({
            "@rules_python//python/config_settings:_is_py_linux_libc_glibc": "glibc",
            "@rules_python//python/config_settings:_is_py_linux_libc_musl": "musl",
            "//conditions:default": "glibc",
        })

    # 6. Wrap with py_extension_wrapper for PEP 3149 naming & PyInfo
    py_extension_wrapper(
        name = name,
        src = ":" + csl_name,
        visibility = visibility,
        **kwargs
    )
