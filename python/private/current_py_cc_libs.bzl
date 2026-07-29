# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Implementation of current_py_cc_libs rule."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _current_py_cc_libs_impl(ctx):
    py_cc_toolchain = ctx.toolchains["//python/cc:toolchain_type"].py_cc_toolchain
    providers = [p for p in py_cc_toolchain.libs.providers_map.values() if not hasattr(p, "data_runfiles")]
    default_runfiles = None
    data_runfiles = None
    files = []
    for p in py_cc_toolchain.libs.providers_map.values():
        if hasattr(p, "data_runfiles"):
            default_runfiles = p.default_runfiles
            data_runfiles = p.data_runfiles

    cc_infos = [p for p in py_cc_toolchain.libs.providers_map.values() if hasattr(p, "linking_context")]
    if cc_infos:
        cc_info = cc_infos[0]
        for input in cc_info.linking_context.linker_inputs.to_list():
            for lib in input.libraries:
                if lib.static_library:
                    files.append(lib.static_library)
                if lib.interface_library:
                    files.append(lib.interface_library)
                elif lib.dynamic_library:
                    files.append(lib.dynamic_library)

    # Filter out .dll files so MSVC link.exe never receives .dll binary files on command line
    link_files = [f for f in files if not f.path.endswith(".dll")]

    providers.append(DefaultInfo(
        files = depset(link_files),
        default_runfiles = default_runfiles,
        data_runfiles = data_runfiles,
    ))
    return providers

current_py_cc_libs = rule(
    implementation = _current_py_cc_libs_impl,
    toolchains = ["//python/cc:toolchain_type"],
    provides = [CcInfo],
    doc = """\
Provides the currently active Python toolchain's C libraries.

This is a wrapper around the underlying `cc_library()` for the
C libraries for the consuming target's currently active Python toolchain.

To use, simply depend on this target where you would have wanted the
toolchain's underlying `:libpython` target:

```starlark
cc_library(
    name = "foo",
    deps = ["@rules_python//python/cc:current_py_cc_libs"]
)
```
""",
)
