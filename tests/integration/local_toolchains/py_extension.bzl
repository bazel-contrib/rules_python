load("@bazel_skylib//rules:copy_file.bzl", "copy_file")

def py_extension(
        name = None,
        srcs = None,
        hdrs = None,
        data = None,
        local_defines = None,
        visibility = None,
        linkopts = None,
        deps = None,
        testonly = False,
        imports = None):
    """Creates a Python module implemented in C++.

    Python modules can depend on a py_extension. Other py_extensions can depend
    on a generated C++ library named with "_cc" suffix.

    Args:
      name: Name for this target.
      srcs: C++ source files.
      hdrs: C++ header files, for other py_extensions which depend on this.
      data: Files needed at runtime. This may include Python libraries.
      visibility: Controls which rules can depend on this.
      deps: Other C++ libraries that this library depends upon.
    """
    if not linkopts:
        linkopts = []

    cc_library_name = name + "_cc"
    cc_binary_so_name = name + ".so"
    cc_binary_dll_name = name + ".dll"
    cc_binary_pyd_name = name + ".pyd"
    linker_script_name = name + ".lds"
    linker_script_name_rule = name + "_lds"
    shared_objects_name = name + "__shared_objects"
    # buildifier: disable=native-cc
    native.cc_library(
        name = cc_library_name,
        srcs = srcs,
        hdrs = hdrs,
        data = data,
        local_defines = local_defines,
        visibility = visibility,
        deps = deps,
        testonly = testonly,
        alwayslink = True,
    )

    # On Unix, restrict symbol visibility.
    exported_symbol = "PyInit_" + name

    # Generate linker script used on non-macOS unix platforms.
    native.genrule(
        name = linker_script_name_rule,
        outs = [linker_script_name],
        cmd = "\n".join([
            "cat <<'EOF' >$@",
            "{",
            "  global: " + exported_symbol + ";",
            "  local: *;",
            "};",
            "EOF",
        ]),
    )

    for cc_binary_name in [cc_binary_dll_name, cc_binary_so_name]:
        cur_linkopts = linkopts
        cur_deps = [cc_library_name]
        if cc_binary_name == cc_binary_so_name:
            cur_linkopts = linkopts + select({
                "@platforms//os:macos": [
                    # Avoid undefined symbol errors for CPython symbols that
                    # will be resolved at runtime.
                    "-undefined",
                    "dynamic_lookup",
                    # On macOS, the linker does not support version scripts.  Use
                    # the `-exported_symbol` option instead to restrict symbol
                    # visibility.
                    "-Wl,-exported_symbol",
                    # On macOS, the symbol starts with an underscore.
                    "-Wl,_" + exported_symbol,
                ],
                # On non-macOS unix, use a version script to restrict symbol
                # visibility.
                "//conditions:default": [
                    "-Wl,--version-script",
                    "-Wl,$(location :" + linker_script_name + ")",
                ],
            })
            cur_deps = cur_deps + select({
                "@platforms//os:macos": [],
                "//conditions:default": [linker_script_name],
            })
        # buildifier: disable=native-cc
        native.cc_binary(
            name = cc_binary_name,
            linkshared = True,
            #linkstatic = True,
            visibility = ["//visibility:private"],
            deps = cur_deps,
            tags = ["manual"],
            testonly = testonly,
            linkopts = cur_linkopts,
        )

    copy_file(
        name = cc_binary_pyd_name + "__pyd_copy",
        src = ":" + cc_binary_dll_name,
        out = cc_binary_pyd_name,
        visibility = visibility,
        tags = ["manual"],
        testonly = testonly,
    )

    native.filegroup(
        name = shared_objects_name,
        data = select({
            "@platforms//os:windows": [
                ":" + cc_binary_pyd_name,
            ],
            "//conditions:default": [":" + cc_binary_so_name],
        }),
        testonly = testonly,
    )

    native.py_library(
        name = name,
        data = [":" + shared_objects_name],
        imports = imports,
        testonly = testonly,
        visibility = visibility,
    )
