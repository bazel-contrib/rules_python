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
_platform_machine_aliases = {
    # These pairs mean the same hardware, but different values may be used
    # on different host platforms.
    "amd64": "x86_64",
    "arm64": "aarch64",
    "i386": "x86_32",
    "i686": "x86_32",
}

# Platform system returns results from the `uname` call.
_platform_system_values = {
    "linux": "Linux",
    "osx": "Darwin",
    "windows": "Windows",
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
    "linux": "linux",
    "osx": "darwin",
    "windows": "win32",
}
_os_name_values = {
    "linux": "posix",
    "osx": "posix",
    "windows": "nt",
}

def env(target_platform, *, extra = None):
    """Return an env target platform

    Args:
        target_platform: {type}`str` the target platform identifier, e.g.
            `cp33_linux_aarch64`
        extra: {type}`str` the extra value to be added into the env.

    Returns:
        A dict that can be used as `env` in the marker evaluation.
    """

    # TODO @aignas 2025-02-13: consider moving this into config settings.

    env = {"extra": extra} if extra != None else {}
    env = env | {
        "implementation_name": "cpython",
        "platform_python_implementation": "CPython",
        "platform_release": "",
        "platform_version": "",
    }

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

    # This is split by topic
    return env | {
        "_aliases": {
            "platform_machine": _platform_machine_aliases,
        },
    }
