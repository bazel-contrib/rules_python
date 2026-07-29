"""Macro for creating Python extensions.

:::{include} /_includes/experimental_api.md
:::
"""

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

    :::{include} /_includes/experimental_api.md
    :::

    By default, extensions are created within their workspace package directory
    (e.g., `pkg/ext.so`) and imported using standard Python package paths
    (e.g., `from pkg import ext`).

    To customize import path behavior:
    - `imports`: Pass `imports = ["..."]` to append custom search directories to
      `sys.path` (matching {attr}`py_library.imports`).
    - `module_name`: Pass `module_name = "custom_name"` to override the base
      module filename.

    Args:
        name: {type}`str` Target name.
        srcs: {type}`list[Label | str] | None` C/C++ source files to compile
            directly for this extension.
        hdrs: {type}`list[Label | str] | None` Header files for `srcs`.
        copts: {type}`list[str] | None` Compiler flags for `srcs`.
        defines: {type}`list[str] | None` Preprocessor defines for `srcs`.
        includes: {type}`list[str] | None` Header include search paths passed
            to internal `cc_library`.
        linkopts: {type}`list[str] | None` Link options passed to internal
            `cc_library` and `cc_shared_library`.
        linkshared: {type}`bool | None` Deprecated and ignored. Extensions are
            always linked dynamically.
        linkstatic: {type}`bool | None` The `linkstatic` flag passed to
            internal `cc_library`.
        deps: {type}`list[Label | str] | None` `cc_library` targets to
            statically link into the extension.
        dynamic_deps: {type}`list[Label | str] | None` `cc_shared_library`
            targets to dynamically link.
        exports_filter: {type}`list[str] | None` Filter for exported symbols
            passed to `cc_shared_library`.
        user_link_flags: {type}`list[str] | None` Additional link flags passed
            to `cc_shared_library`.
        visibility: {type}`list[Label | str] | None` Target visibility.
        data: {type}`list[Label | str] | None` List of files or targets needed
            by this extension at runtime.
        **kwargs: {type}`dict` Additional arguments passed to the underlying
            wrapper rule.
    """
    add_tag(kwargs, "@rules_python//python/cc:py_extension")
    _ = linkshared  # buildifier: disable=unused-variable

    csl_deps = []

    py_cc_headers_and_win_libs = [
        "@rules_python//python/cc:current_py_cc_headers",
    ] + select({
        "@platforms//os:windows": ["@rules_python//python/cc:current_py_cc_libs"],
        "//conditions:default": [],
    })

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
            deps = (deps or []) + py_cc_headers_and_win_libs,
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

    mod_name = kwargs.get("module_name") or name
    win_export_flags = [
        "$(locations @rules_python//python/cc:current_py_cc_libs)",
        "/EXPORT:PyInit_" + mod_name,
    ]
    if kwargs.get("py_limited_api"):
        win_export_flags.append("/EXPORT:PyInitU_" + mod_name)

    effective_user_link_flags = (user_link_flags or linkopts or []) + select({
        "@platforms//os:macos": ["-undefined", "dynamic_lookup"],
        "@platforms//os:osx": ["-undefined", "dynamic_lookup"],
        "@platforms//os:windows": win_export_flags,
        "//conditions:default": [],
    })
    csl_kwargs["user_link_flags"] = effective_user_link_flags

    csl_additional_linker_inputs = select({
        "@platforms//os:windows": ["@rules_python//python/cc:current_py_cc_libs"],
        "//conditions:default": [],
    })

    if exports_filter:
        csl_kwargs["exports_filter"] = exports_filter

    cc_shared_library(
        name = csl_name,
        deps = csl_deps,
        additional_linker_inputs = csl_additional_linker_inputs,
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
