"""Macro for creating Python extensions."""

load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_shared_library.bzl", "cc_shared_library")
load("//python/private:util.bzl", "add_tag", "copy_propagating_kwargs")
load(":py_extension_rule.bzl", "py_extension_wrapper")

def py_extension(
        name,
        srcs = None,
        hdrs = None,
        copts = None,
        defines = None,
        includes = None,
        linkopts = None,
        linkshared = None,
        linkstatic = None,
        deps = None,
        dynamic_deps = None,
        exports_filter = None,
        user_link_flags = None,
        visibility = None,
        data = None,
        **kwargs):
    """Creates a Python extension module.

    By default, extensions are created within their workspace package directory
    (e.g., `pkg/ext.so`) and imported using standard Python package paths
    (e.g., `from pkg import ext`).

    To customize import path behavior:
    - `imports`: Pass `imports = ["..."]` to append custom search directories to
      `sys.path` (matching `py_library`).
    - `module_name`: Pass `module_name = "custom_name"` to override the base module
      filename.

    Args:
        name: Target name.
        srcs: Optional C/C++ source files to compile directly for this extension.
        hdrs: Optional header files for the srcs.
        copts: Optional compiler flags for srcs.
        defines: Optional preprocessor defines for srcs.
        includes: Optional header include search paths passed to internal cc_library.
        linkopts: Optional link options passed to internal cc_library and cc_shared_library.
        linkshared: Deprecated and ignored. Extensions are always linked dynamically.
        linkstatic: Optional linkstatic flag passed to internal cc_library.
        deps: cc_library targets to statically link into the extension.
        dynamic_deps: cc_shared_library targets to dynamically link.
        exports_filter: Filter for exported symbols passed to cc_shared_library.
        user_link_flags: Additional link flags passed to cc_shared_library.
        visibility: Target visibility.
        data: Optional list of files or targets needed by this extension at runtime.
        **kwargs: Additional arguments passed to the underlying wrapper rule.
    """
    add_tag(kwargs, "@rules_python//python/cc:py_extension")
    _ = linkshared  # buildifier: disable=unused-variable

    csl_deps = []

    # 1. If srcs or hdrs are specified, create an implicit cc_library for them
    if srcs or hdrs:
        impl_lib_name = "_" + name + "_impl"
        impl_lib_kwargs = copy_propagating_kwargs(kwargs)
        if includes:
            impl_lib_kwargs["includes"] = includes
        if linkopts:
            impl_lib_kwargs["linkopts"] = linkopts
        if linkstatic != None:
            impl_lib_kwargs["linkstatic"] = linkstatic
        cc_library(
            name = impl_lib_name,
            srcs = srcs,
            hdrs = hdrs,
            copts = (copts or []) + ["-fPIC"],
            defines = defines,
            deps = (deps or []) + ["@rules_python//python/cc:current_py_cc_headers"],
            visibility = ["//visibility:private"],
            **impl_lib_kwargs
        )
        csl_deps.append(":" + impl_lib_name)
    elif deps:
        csl_deps.extend(deps)

    # 2. If no static deps or sources were specified, use empty target for CSL requirement
    if not csl_deps:
        csl_deps.append("//python/private/cc:empty")

    # 4. Create the underlying cc_shared_library
    csl_name = "_" + name + "_csl"
    csl_kwargs = copy_propagating_kwargs(kwargs)
    if exports_filter:
        csl_kwargs["exports_filter"] = exports_filter
    effective_user_link_flags = user_link_flags or linkopts
    if effective_user_link_flags:
        csl_kwargs["user_link_flags"] = effective_user_link_flags

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

    if data != None:
        kwargs["data"] = data

    # 6. Filter out C++ specific compilation/linking attributes before invoking wrapper rule
    for cc_attr in ("includes", "linkopts", "linkshared", "linkstatic", "features"):
        kwargs.pop(cc_attr, None)

    # 7. Wrap with py_extension_wrapper for PEP 3149 naming & PyInfo
    py_extension_wrapper(
        name = name,
        src = ":" + csl_name,
        visibility = visibility,
        **kwargs
    )
