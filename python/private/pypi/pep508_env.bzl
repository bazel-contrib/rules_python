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

"""This module is for implementing PEP508 environment definition.
"""

load(":pep508_platform.bzl", "platform_from_str")

# See https://stackoverflow.com/a/45125525
platform_machine_aliases = {
    # These pairs mean the same hardware, but different values may be used
    # on different host platforms.
    "amd64": "x86_64",
    "arm64": "aarch64",
    "i386": "x86_32",
    "i686": "x86_32",
}

# NOTE: There are many cpus, and unfortunately, the value isn't directly
# accessible to Starlark. Using CcToolchain.cpu might work, though.
# Some targets are aliases and are omitted below as their value is implied
# by the target they resolve to.
platform_machine_select_map = {
    "@platforms//cpu:aarch32": "aarch32",
    "@platforms//cpu:aarch64": "aarch64",
    # @platforms//cpu:arm is an alias for @platforms//cpu:aarch32
    # @platforms//cpu:arm64 is an alias for @platforms//cpu:aarch64
    "@platforms//cpu:arm64_32": "arm64_32",
    "@platforms//cpu:arm64e": "arm64e",
    "@platforms//cpu:armv6-m": "armv6-m",
    "@platforms//cpu:armv7": "armv7",
    "@platforms//cpu:armv7-m": "armv7-m",
    "@platforms//cpu:armv7e-m": "armv7e-m",
    "@platforms//cpu:armv7e-mf": "armv7e-mf",
    "@platforms//cpu:armv7k": "armv7k",
    "@platforms//cpu:armv8-m": "armv8-m",
    "@platforms//cpu:cortex-r52": "cortex-r52",
    "@platforms//cpu:cortex-r82": "cortex-r82",
    "@platforms//cpu:i386": "i386",
    "@platforms//cpu:mips64": "mips64",
    "@platforms//cpu:ppc": "ppc",
    "@platforms//cpu:ppc32": "ppc32",
    "@platforms//cpu:ppc64le": "ppc64le",
    "@platforms//cpu:riscv32": "riscv32",
    "@platforms//cpu:riscv64": "riscv64",
    "@platforms//cpu:s390x": "s390x",
    "@platforms//cpu:wasm32": "wasm32",
    "@platforms//cpu:wasm64": "wasm64",
    "@platforms//cpu:x86_32": "x86_32",
    "@platforms//cpu:x86_64": "x86_64",
    # The value is empty string if it cannot be determined:
    # https://docs.python.org/3/library/platform.html#platform.machine
    "//conditions:default": "",
}

# Platform system returns results from the `uname` call.
_platform_system_values = {
    # See https://peps.python.org/pep-0738/#platform
    "android": "Android",
    "freebsd": "FreeBSD",
    # See https://peps.python.org/pep-0730/#platform
    # NOTE: Per Pep 730, "iPadOS" is also an acceptable value
    "ios": "iOS",
    "linux": "Linux",
    "netbsd": "NetBSD",
    "openbsd": "OpenBSD",
    "osx": "Darwin",
    "windows": "Windows",
}

platform_system_select_map = {
    "@platforms//os:{}".format(bazel_os): py_system
    for bazel_os, py_system in _platform_system_values.items()
} | {
    # The value is empty string if it cannot be determined:
    # https://docs.python.org/3/library/platform.html#platform.machine
    "//conditions:default": "",
}

# The copy of SO [answer](https://stackoverflow.com/a/13874620) containing
# all of the platforms:
# ┍━━━━━━━━━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━┑
# │ System              │ Value               │
# ┝━━━━━━━━━━━━━━━━━━━━━┿━━━━━━━━━━━━━━━━━━━━━┥
# │ Linux               │ linux or linux2 (*) │
# │ Windows             │ win32               │
# │ Windows/Cygwin      │ cygwin              │
# │ Windows/MSYS2       │ msys                │
# │ Mac OS X            │ darwin              │
# │ OS/2                │ os2                 │
# │ OS/2 EMX            │ os2emx              │
# │ RiscOS              │ riscos              │
# │ AtheOS              │ atheos              │
# │ FreeBSD 7           │ freebsd7            │
# │ FreeBSD 8           │ freebsd8            │
# │ FreeBSD N           │ freebsdN            │
# │ OpenBSD 6           │ openbsd6            │
# │ AIX                 │ aix (**)            │
# ┕━━━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━┙
#
# (*) Prior to Python 3.3, the value for any Linux version is always linux2; after, it is linux.
# (**) Prior Python 3.8 could also be aix5 or aix7; use sys.platform.startswith()
#
# We are using only the subset that we actually support.
_sys_platform_values = {
    # These values are decided by the sys.platform docs.
    "android": "android",
    "emscripten": "emscripten",
    # NOTE: The below values are approximations. The sys.platform() docs
    # don't have documented values for these OSes. Per docs, the
    # sys.platform() value reflects the OS at the time Python was *built*
    # instead of the runtime (target) OS value.
    "freebsd": "freebsd",
    "ios": "ios",
    "linux": "linux",
    "openbsd": "openbsd",
    "osx": "darwin",
    "wasi": "wasi",
    "windows": "win32",
}

sys_platform_select_map = {
    "@platforms//os:{}".format(bazel_os): py_platform
    for bazel_os, py_platform in _sys_platform_values.items()
} | {
    # For lack of a better option, use empty string. No standard doc/spec
    # about sys_platform value.
    "//conditions:default": "",
}

# The "java" value is documented, but with Jython defunct,
# shouldn't occur in practice.
# The os.name value is technically a property of the runtime, not the
# targetted runtime OS, but the distinction shouldn't matter if
# things are properly configured.
_os_name_values = {
    "linux": "posix",
    "osx": "posix",
    "windows": "nt",
}

os_name_select_map = {
    "@platforms//os:{}".format(bazel_os): py_os
    for bazel_os, py_os in _os_name_values.items()
} | {
    "//conditions:default": "posix",
}

def env(target_platform, *, extra = None):
    """Return an env target platform

    NOTE: This is for use during the loading phase. For the analysis phase,
    `env_marker_setting()` constructs the env dict.

    Args:
        target_platform: {type}`str` the target platform identifier, e.g.
            `cp33_linux_aarch64`
        extra: {type}`str` the extra value to be added into the env.

    Returns:
        A dict that can be used as `env` in the marker evaluation.
    """
    env = create_env()
    if extra != None:
        env["extra"] = extra

    if type(target_platform) == type(""):
        target_platform = platform_from_str(target_platform, python_version = "")

    if target_platform.abi:
        minor_version, _, micro_version = target_platform.abi[3:].partition(".")
        micro_version = micro_version or "0"
        env = env | {
            "implementation_version": "3.{}.{}".format(minor_version, micro_version),
            "python_full_version": "3.{}.{}".format(minor_version, micro_version),
            "python_version": "3.{}".format(minor_version),
        }
    if target_platform.os and target_platform.arch:
        os = target_platform.os
        env = env | {
            "os_name": _os_name_values.get(os, ""),
            "platform_machine": target_platform.arch,
            "platform_system": _platform_system_values.get(os, ""),
            "sys_platform": _sys_platform_values.get(os, ""),
        }
    set_missing_env_defaults(env)

    return env

def create_env():
    return {
        # This is split by topic
        "_aliases": {
            "platform_machine": platform_machine_aliases,
        },
    }

def set_missing_env_defaults(env):
    """Sets defaults based on existing values.

    Args:
        env: dict; NOTE: modified in-place
    """
    if "implementation_name" not in env:
        # Use cpython as the default because it's likely the correct value.
        env["implementation_name"] = "cpython"
    if "platform_python_implementation" not in env:
        # The `platform_python_implementation` marker value is supposed to come
        # from `platform.python_implementation()`, however, PEP 421 introduced
        # `sys.implementation.name` and the `implementation_name` env marker to
        # replace it. Per the platform.python_implementation docs, there's now
        # essentially just two possible "registered" values: CPython or PyPy.
        # Rather than add a field to the toolchain, we just special case the value
        # from `sys.implementation.name` to handle the two documented values.
        platform_python_impl = env["implementation_name"]
        if platform_python_impl == "cpython":
            platform_python_impl = "CPython"
        elif platform_python_impl == "pypy":
            platform_python_impl = "PyPy"
        env["platform_python_implementation"] = platform_python_impl
    if "platform_release" not in env:
        env["platform_release"] = ""
    if "platform_version" not in env:
        env["platform_version"] = "0"
