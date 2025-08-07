# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import json
import os
import sys
import sysconfig

_IS_WINDOWS = sys.platform == "win32"
_IS_DARWIN = sys.platform == "darwin"


def _search_directories(get_config):
    """Returns a list of library directories to search for shared libraries."""
    # There's several types of libraries with different names and a plethora
    # of settings, and many different config variables to check:
    #
    # LIBPL is used in python-config when shared library is not enabled:
    # https://github.com/python/cpython/blob/v3.12.0/Misc/python-config.in#L63
    #
    # LIBDIR may also be the python directory with library files.
    # https://stackoverflow.com/questions/47423246/get-pythons-lib-path
    # See also: MULTIARCH
    #
    # On MacOS, the LDLIBRARY may be a relative path under /Library/Frameworks,
    # such as "Python.framework/Versions/3.12/Python", not a file under the
    # LIBDIR/LIBPL directory, so include PYTHONFRAMEWORKPREFIX.
    lib_dirs = [get_config(x) for x in ("PYTHONFRAMEWORKPREFIX", "LIBPL", "LIBDIR")]

    # On Debian, with multiarch enabled, prior to Python 3.10, `LIBDIR` didn't
    # tell the location of the libs, just the base directory. The `MULTIARCH`
    # sysconfig variable tells the subdirectory within it with the libs.
    # See:
    # https://wiki.debian.org/Python/MultiArch
    # https://git.launchpad.net/ubuntu/+source/python3.12/tree/debian/changelog#n842
    multiarch = get_config("MULTIARCH")
    if multiarch:
        for x in ["LIBPL", "LIBDIR"]:
            config_value = get_config(x)
            if config_value and not config_value.endswith(multiarch):
                lib_dirs.append(os.path.join(config_value, multiarch))

    if _IS_WINDOWS:
        # On Windows DLLs go in the same directory as the executable, while .lib
        # files live in the lib/ or libs/ subdirectory.
        lib_dirs.append(get_config("BINDIR"))
        lib_dirs.append(os.path.join(os.path.dirname(sys.executable)))
        lib_dirs.append(os.path.join(os.path.dirname(sys.executable), "lib"))
        lib_dirs.append(os.path.join(os.path.dirname(sys.executable), "libs"))
    elif not _IS_DARWIN:
        # On most systems the executable is in a bin/ directory and the libraries
        # are in a sibling lib/ directory.
        lib_dirs.append(
            os.path.join(os.path.dirname(os.path.dirname(sys.executable)), "lib")
        )

    # Dedup and remove empty values, keeping the order.
    lib_dirs = [v for v in lib_dirs if v]
    return {k: None for k in lib_dirs}.keys()


def _search_library_names(get_config):
    """Returns a list of library files to search for shared libraries."""
    # Quoting configure.ac in the cpython code base:
    # "INSTSONAME is the name of the shared library that will be use to install
    # on the system - some systems like version suffix, others don't.""
    #
    # A typical INSTSONAME is 'libpython3.8.so.1.0' on Linux, or
    # 'Python.framework/Versions/3.9/Python' on MacOS. Due to the possible
    # version suffix we have to find the suffix within the filename.
    #
    # A typical LDLIBRARY is 'libpythonX.Y.so' on Linux, or 'pythonXY.dll' on
    # Windows.
    #
    # A typical LIBRARY is 'libpythonX.Y.a' on Linux.
    lib_names = [
        get_config(x)
        for x in (
            "INSTSONAME",
            "LDLIBRARY",
            "PY3LIBRARY",
            "LIBRARY",
            "DLLLIBRARY",
        )
    ]

    if _IS_WINDOWS:
        so_prefix = ""
    else:
        so_prefix = "lib"

    # Get/override the SHLIB_SUFFIX, which is typically ".so" on Linux and
    # ".dylib" on macOS.
    so_suffix = get_config("SHLIB_SUFFIX")
    if _IS_DARWIN:
        # SHLIB_SUFFIX may be ".so"; always override on darwin to be ".dynlib"
        so_suffix = ".dylib"
    elif _IS_WINDOWS:
        # While the suffix is ".dll", the compiler needs to link with the ".lib" file.
        so_suffix = ".lib"
    elif not so_suffix:
        so_suffix = ".so"

    version = get_config("VERSION")
    abiflags = get_config("ABIFLAGS") or get_config("abiflags") or ""

    # On Windows, extensions should link with the pythonXY.lib files.
    # See: https://docs.python.org/3/extending/windows.html
    # So ensure that the pythonXY.lib files are included in the search.
    if abiflags:
        lib_names.append(f"{so_prefix}python{version}{abiflags}{so_suffix}")
    lib_names.append(f"{so_prefix}python{version}{so_suffix}")

    # Dedup and remove empty values, keeping the order.
    lib_names = [v for v in lib_names if v]
    return {k: None for k in lib_names}.keys()


def _get_python_library_info():
    """Returns a dictionary with the static and dynamic python libraries."""
    config_vars = sysconfig.get_config_vars()

    # VERSION is X.Y in Linux/macOS and XY in Windows.
    if not config_vars.get("VERSION"):
        if sys.platform == "win32":
            config_vars["VERSION"] = f"{sys.version_info.major}{sys.version_info.minor}"
        else:
            config_vars["VERSION"] = (
                f"{sys.version_info.major}.{sys.version_info.minor}"
            )

    search_directories = _search_directories(config_vars.get)
    search_libnames = _search_library_names(config_vars.get)

    dynamic_libraries = {}
    static_libraries = {}
    for root_dir in search_directories:
        for libname in search_libnames:
            composed_path = os.path.join(root_dir, libname)
            if not os.path.exists(composed_path) or os.path.isdir(composed_path):
                continue
            if composed_path.endswith(".lib") or composed_path.endswith(".a"):
                static_libraries[composed_path] = None
            else:
                dynamic_libraries[composed_path] = None

    # When no libraries are found it's likely that the python interpreter is not
    # configured to use shared or static libraries (minilinux).  If this seems
    # suspicious try running `uv tool run find_libpython --list-all -v`
    return {
        "dynamic_libraries": list(dynamic_libraries.keys()),
        "static_libraries": list(static_libraries.keys()),
    }


data = {
    "major": sys.version_info.major,
    "minor": sys.version_info.minor,
    "micro": sys.version_info.micro,
    "include": sysconfig.get_path("include"),
    "implementation_name": sys.implementation.name,
    "base_executable": sys._base_executable,
}
data.update(_get_python_library_info())
print(json.dumps(data))
