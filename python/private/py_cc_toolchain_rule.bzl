# Copyright 2023 The Bazel Authors. All rights reserved.
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

"""Implementation of py_cc_toolchain rule.

NOTE: This is a beta-quality feature. APIs subject to change until
https://github.com/bazel-contrib/rules_python/issues/824 is considered done.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":common_labels.bzl", "labels")
load(":flags.bzl", "FreeThreadedFlag")
load(":py_cc_toolchain_info.bzl", "PyCcToolchainInfo")
load(":sentinel.bzl", "SentinelInfo")

def _get_platform_tag(os, cpu, libc):
    """
    Derives the PEP 3149 platform tag string based on target OS, CPU, and
    libc. Note that these are platform tags for C extension filenames, not
    PEP 425 tags for wheels.

    Linux platform tags are standardized here:
      - https://peps.python.org/pep-3149/
    Windows platform tags, such as they are, are defined in this issue and
            commit (treated as a de facto standard):
      - https://github.com/python/cpython/issues/67169
      - https://github.com/python/cpython/commit/03a144bb6ac3d7631a3bdb895e2a1f2d021fb08b
    Apple platform tag is always just "darwin", discussed briefly here:
      - https://github.com/python/cpython/commit/3b8124884c3655b4cf2629d741b18c1a38181805

    Args:
        os: Target OS, e.g. "windows", "macos", "linux"
        cpu: Target CPU architecture, e.g. "x86_64", "aarch64", "x86_32"
        libc: Target C library variant, e.g. "gnu", "musl"

    Returns:
        The platform tag, e.g. "x86_64-linux-gnu", "darwin", or "win_amd64"
    """
    if os == "windows":
        if cpu == "x86_64":
            return "win_amd64"
        if cpu == "aarch64":
            return "win_arm64"
        return "win32"
    if os == "macos":
        return "darwin"

    cpu_val = cpu if cpu else "x86_64"
    libc_val = libc if libc else "gnu"
    return "{}-linux-{}".format(cpu_val, libc_val)

def _py_cc_toolchain_impl(ctx):
    if ctx.attr.libs:
        libs = struct(
            providers_map = {
                "CcInfo": ctx.attr.libs[CcInfo],
                "DefaultInfo": ctx.attr.libs[DefaultInfo],
            },
        )
    else:
        libs = None

    if ctx.attr.headers_abi3 and SentinelInfo not in ctx.attr.headers_abi3:
        headers_abi3 = struct(
            providers_map = {
                "CcInfo": ctx.attr.headers_abi3[CcInfo],
                "DefaultInfo": ctx.attr.headers_abi3[DefaultInfo],
            },
        )
    else:
        headers_abi3 = None

    abi_tag = ctx.attr.abi_tag
    if not abi_tag:
        # Derive default: cpython-XX[t]
        version_parts = ctx.attr.python_version.split(".")
        abi_flags = ""
        if ctx.attr._py_freethreaded_flag[BuildSettingInfo].value == FreeThreadedFlag.YES:
            abi_flags += "t"
        abi_tag = "cpython-{}{}{}".format(version_parts[0], version_parts[1], abi_flags)

    platform_tag = _get_platform_tag(
        os = ctx.attr.os,
        cpu = ctx.attr.cpu,
        libc = ctx.attr.libc,
    )

    py_cc_toolchain = PyCcToolchainInfo(
        abi_tag = abi_tag,
        platform_tag = platform_tag,
        headers = struct(
            providers_map = {
                "CcInfo": ctx.attr.headers[CcInfo],
                "DefaultInfo": ctx.attr.headers[DefaultInfo],
            },
        ),
        headers_abi3 = headers_abi3,
        libs = libs,
        python_version = ctx.attr.python_version,
    )
    extra_kwargs = {}
    if ctx.attr._visible_for_testing[BuildSettingInfo].value:
        extra_kwargs["toolchain_label"] = ctx.label
    return [platform_common.ToolchainInfo(
        py_cc_toolchain = py_cc_toolchain,
        **extra_kwargs
    )]

py_cc_toolchain = rule(
    implementation = _py_cc_toolchain_impl,
    attrs = {
        "abi_tag": attr.string(
            doc = "The ABI tag for extension modules, e.g. 'cpython-311'",
            default = "",
        ),
        "cpu": attr.string(
            doc = "Target CPU architecture, e.g. 'x86_64', 'aarch64', 'x86_32'",
            default = "",
        ),
        "headers": attr.label(
            doc = ("Target that provides the Python headers. Typically this " +
                   "is a cc_library target."),
            providers = [CcInfo],
            mandatory = True,
        ),
        "headers_abi3": attr.label(
            doc = """
Target that provides the Python ABI3 (stable abi) headers.

Typically this is a cc_library target.

:::{versionadded} VERSION_NEXT_FEATURE
The {obj}`features.headers_abi3` attribute can be used to detect if this
attribute is available or not.
:::
""",
            default = "//python:none",
            providers = [[SentinelInfo], [CcInfo]],
        ),
        "libc": attr.string(
            doc = "Target C library variant, e.g. 'gnu', 'musl'",
            default = "",
        ),
        "libs": attr.label(
            doc = ("Target that provides the Python runtime libraries for linking. " +
                   "Typically this is a cc_library target of `.so` files."),
            providers = [CcInfo],
        ),
        "os": attr.string(
            doc = "Target OS, e.g. 'linux', 'macos', 'windows'",
            default = "",
        ),
        "python_version": attr.string(
            doc = "The Major.minor Python version, e.g. 3.11",
            mandatory = True,
        ),
        "_py_freethreaded_flag": attr.label(
            default = labels.PY_FREETHREADED,
        ),
        "_visible_for_testing": attr.label(
            default = labels.VISIBLE_FOR_TESTING,
        ),
    },
    doc = """
A toolchain for a Python runtime's C/C++ information (e.g. headers)

This rule carries information about the C/C++ side of a Python runtime, e.g.
headers, shared libraries, etc.

This provides `ToolchainInfo` with the following attributes:
* `py_cc_toolchain`: {type}`PyCcToolchainInfo`
* `toolchain_label`: {type}`Label` _only present when `--visibile_for_testing=True`
  for internal testing_. The rule's label; this allows identifying what toolchain
  implmentation was selected for testing purposes.
""",
)
