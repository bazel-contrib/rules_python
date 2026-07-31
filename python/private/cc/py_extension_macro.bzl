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
        local_defines = None,
        includes = None,
        linkopts = None,
        deps = None,
        dynamic_deps = None,
        exports_filter = None,
        user_link_flags = None,
        additional_linker_inputs = None,
        module_name = None,
        py_limited_api = None,
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
        local_defines: {type}`list[str] | None` Preprocessor defines for `srcs`
            passed to internal `cc_library`.
        includes: {type}`list[str] | None` Header include search paths passed
            to internal `cc_library`.
        linkopts: {type}`list[str] | None` Link options passed to internal
            `cc_library` created for `srcs`/`hdrs`. To pass linker flags to
            `cc_shared_library`, use `user_link_flags`.
        deps: {type}`list[Label | str] | None` `cc_library` targets to
            statically link into the extension.
        dynamic_deps: {type}`list[Label | str] | None` `cc_shared_library`
            targets to dynamically link.
        exports_filter: {type}`list[str] | None` Filter for exported symbols
            passed to `cc_shared_library`.
        user_link_flags: {type}`list[str] | None` Additional link flags passed
            to `cc_shared_library`. To pass linker flags that apply to `srcs`,
            use `linkopts`.
        additional_linker_inputs: {type}`list[Label | str] | None` Additional
            linker inputs passed to `cc_shared_library`.
        module_name: {type}`str | None` Custom Python module name. If not set,
            defaults to `name`.
        py_limited_api: {type}`str | None` Python limited API version string
            (e.g., `"3.8"`).
        **kwargs: {type}`dict` Additional arguments passed to the underlying
            wrapper rule.
    """
    add_tag(kwargs, "@rules_python//python/cc:py_extension")
    user_link_flags = user_link_flags or []

    csl_deps = []

    copts = (copts or []) + [
        # -fPIC (Position Independent Code) is required when compiling C/C++ sources into
        # dynamic/shared libraries (.so/.dylib/.pyd) so code can be loaded at arbitrary addresses.
        "-fPIC",
    ]

    py_cc_headers_alias = str(Label("//python/private/cc:current_py_cc_headers_private_alias"))
    py_cc_libs_alias = str(Label("//python/private/cc:current_py_cc_libs_private_alias"))
    py_cc_libs_target = str(Label("//python/cc:current_py_cc_libs"))

    # Private alias targets are appended to avoid "duplicate dependency label" errors
    # if a user explicitly passes //python/cc:current_py_cc_headers or //python/cc:current_py_cc_libs
    # in their deps attribute (including when deps is a select() expression).
    py_cc_headers_and_win_libs = [
        py_cc_headers_alias,
    ] + select({
        "@platforms//os:windows": [py_cc_libs_alias],
        "//conditions:default": [],
    })
    deps = (deps or []) + py_cc_headers_and_win_libs

    # 1. If srcs or hdrs are specified, create an implicit cc_library for them
    if srcs or hdrs:
        impl_lib_name = "_" + name + "_impl"
        impl_lib_kwargs = copy_propagating_kwargs(kwargs)
        if includes:
            impl_lib_kwargs["includes"] = includes
        if linkopts:
            impl_lib_kwargs["linkopts"] = linkopts
        cc_library(
            name = impl_lib_name,
            srcs = srcs,
            hdrs = hdrs,
            copts = copts,
            defines = defines,
            local_defines = local_defines,
            deps = deps,
            visibility = ["//visibility:private"],
            **impl_lib_kwargs
        )
        csl_deps.append(":" + impl_lib_name)

    if csl_deps:
        final_csl_deps = csl_deps
    elif deps:
        final_csl_deps = deps
    else:
        # cc_shared_library requires a dependency, so use an empty library when none are given.
        final_csl_deps = ["//python/private/cc:empty"]

    # 4. Create the underlying cc_shared_library
    csl_name = "_" + name + "_csl"
    csl_kwargs = copy_propagating_kwargs(kwargs)

    if srcs or hdrs:
        csl_deps_with_win = final_csl_deps + select({
            "@platforms//os:windows": [py_cc_libs_alias],
            "//conditions:default": [],
        })
    else:
        csl_deps_with_win = final_csl_deps

    win_exports_filter = select({
        "@platforms//os:windows": [py_cc_libs_target, py_cc_libs_alias],
        "//conditions:default": [],
    })

    # exports_filter specifies which target dependencies should have their exported
    # symbols exposed by cc_shared_library. On Windows MSVC, cc_shared_library uses
    # exports_filter to inspect the .obj files of matching targets and generate a .def
    # file containing all __declspec(dllexport) symbols (such as PyInit_<name>).
    # Defaulting to csl_deps_with_win + win_exports_filter ensures only the targets in
    # this extension (e.g. _impl) and Windows CPython import libraries (both alias and
    # actual resolved target) are included and inspected, rather than all targets in the package.
    csl_kwargs["exports_filter"] = exports_filter if exports_filter != None else (csl_deps_with_win + win_exports_filter)

    effective_user_link_flags = user_link_flags + select({
        # On macOS, Apple's ld64 linker requires '-undefined dynamic_lookup' so CPython
        # C-API symbols (e.g. PyModule_Create) remain unresolved at link time and are
        # dynamically resolved at runtime when CPython loads the shared library (.so).
        "@platforms//os:macos": ["-undefined", "dynamic_lookup"],
        "//conditions:default": [],
    })
    csl_kwargs["user_link_flags"] = effective_user_link_flags

    cc_shared_library(
        name = csl_name,
        deps = csl_deps_with_win,
        additional_linker_inputs = additional_linker_inputs,
        dynamic_deps = dynamic_deps,
        visibility = ["//visibility:private"],
        **csl_kwargs
    )

    # 5. Propagate attributes to wrapper rule
    kwargs["module_name"] = module_name
    kwargs["py_limited_api"] = py_limited_api

    # 6. Filter out C++ specific compilation/linking attributes before invoking wrapper rule
    for cc_attr in ("includes", "linkopts", "linkshared", "linkstatic", "features"):
        kwargs.pop(cc_attr, None)

    # 7. Wrap with py_extension_wrapper for PEP 3149 naming & PyInfo
    py_extension_wrapper(
        name = name,
        src = ":" + csl_name,
        **kwargs
    )
