# Copyright 2025 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Macro to build a python C/C++ extension.

There are variants of py_extension in many other projects, such as:
https://github.com/protocolbuffers/protobuf/tree/main/python/py_extension.bzl
https://github.com/google/riegeli/blob/master/python/riegeli/py_extension.bzl
https://github.com/pybind/pybind11_bazel/blob/master/build_defs.bzl
"""

load("@bazel_skylib//rules:copy_file.bzl", "copy_file")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_python//python:defs.bzl", "py_library")

def py_extension(
        *,
        name,
        srcs = None,
        hdrs = None,
        deps = None,
        linkopts = None,
        imports = None,
        **kwargs):
    """Creates a Python module implemented in C++.

    A Python extension has 3 essential parts:
      1.  The cc_library target for the extension, which is `name_cc`
      2.  The shared object / pyd package for the extension, `name.pyd`/`name.so`
      3.  The py_library target for the extension, which is `name`

    Python modules can depend on a py_extension. Other py_extensions can depend
    on the generated C++ library named with "_cc" suffix.

    Args:
      name: `str`. Name for this target.  This is typically the module name.
      srcs: `list`. C++ source files.
      hdrs: `list`. C++ header files, for other py_extensions which depend on this.
      deps: `list`. Other C++ libraries that this library depends upon.
      linkopts: `list`. Linking options for the shared library.
      imports: `list`. Additional imports for the py_library rule.
      **kwargs:  Additional options for the cc_library rule.
    """
    if not name:
        fail("py_extension requires a name")

    if not linkopts:
        linkopts = []

    testonly = kwargs.get("testonly")
    visibility = kwargs.get("visibility")

    cc_library_name = name + "_cc"
    cc_binary_so_name = name + ".so"
    cc_binary_dll_name = name + ".dll"
    cc_binary_pyd_name = name + ".pyd"
    linker_script_name = name + ".lds"
    linker_script_name_rule = name + "_lds"
    shared_objects_name = name + "__shared_objects"

    cc_library(
        name = cc_library_name,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        alwayslink = True,
        **kwargs
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
            }) + select({
                "@rules_cc//cc/compiler:msvc-cl": [],
                "//conditions:default": ["-fvisibility=hidden"],
            })
            cur_deps = cur_deps + select({
                "@platforms//os:macos": [],
                "//conditions:default": [linker_script_name],
            })

        cc_binary(
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
    py_library(
        name = name,
        data = [":" + shared_objects_name],
        imports = imports,
        testonly = testonly,
        visibility = visibility,
    )
