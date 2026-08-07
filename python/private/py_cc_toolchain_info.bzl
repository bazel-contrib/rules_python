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

"""Implementation of PyCcToolchainInfo."""

PyCcToolchainInfo = provider(
    doc = "C/C++ information about the Python runtime.",
    fields = {
        "abi_flags": """\
:type: str

The runtime's ABI flags, i.e. `sys.abiflags` (e.g. 't' for free-threaded builds).

:::{versionadded} 2.3.0
:::
""",
        "headers": """\
:type: struct

Information about the header files, struct with fields:
  * providers_map: a dict of string to provider instances. The key should be
    a fully qualified name (e.g. `@rules_foo//bar:baz.bzl#MyInfo`) of the
    provider to uniquely identify its type.

    The following keys are always present:
      * CcInfo: the CcInfo provider instance for the headers.
      * DefaultInfo: the DefaultInfo provider instance for the headers.

    A map is used to allow additional providers from the originating headers
    target (typically a `cc_library`) to be propagated to consumers (directly
    exposing a Target object can cause memory issues and is an anti-pattern).

    When consuming this map, it's suggested to use `providers_map.values()` to
    return all providers; or copy the map and filter out or replace keys as
    appropriate. Note that any keys beginning with `_` (underscore) are
    considered private and should be forward along as-is (this better allows
    e.g. `:current_py_cc_headers` to act as the underlying headers target it
    represents).
""",
        "headers_abi3": """
:type: struct | None

If available, information about ABI3 (stable ABI) header files, struct with
fields:
  * providers_map: a dict of string to provider instances. The key should be
    a fully qualified name (e.g. `@rules_foo//bar:baz.bzl#MyInfo`) of the
    provider to uniquely identify its type.

    The following keys are always present:
      * CcInfo: the CcInfo provider instance for the headers.
      * DefaultInfo: the DefaultInfo provider instance for the headers.

    A map is used to allow additional providers from the originating headers
    target (typically a `cc_library`) to be propagated to consumers (directly
    exposing a Target object can cause memory issues and is an anti-pattern).

    When consuming this map, it's suggested to use `providers_map.values()` to
    return all providers; or copy the map and filter out or replace keys as
    appropriate. Note that any keys beginning with `_` (underscore) are
    considered private and should be forward along as-is (this better allows
    e.g. `:current_py_cc_headers` to act as the underlying headers target it
    represents).

:::{versionadded} 1.7.0
The {obj}`features.headers_abi3` attribute can be used to detect if this
attribute is available or not.
:::
""",
        "libs": """
:type: struct | None

If available, information about C libraries, struct with fields:
  * providers_map: A dict of string to provider instances. The key should be
    a fully qualified name (e.g. `@rules_foo//bar:baz.bzl#MyInfo`) of the
    provider to uniquely identify its type.

    The following keys are always present:
      * CcInfo: the CcInfo provider instance for the libraries.
      * DefaultInfo: the DefaultInfo provider instance for the headers.

    A map is used to allow additional providers from the originating libraries
    target (typically a `cc_library`) to be propagated to consumers (directly
    exposing a Target object can cause memory issues and is an anti-pattern).

    When consuming this map, it's suggested to use `providers_map.values()` to
    return all providers; or copy the map and filter out or replace keys as
    appropriate. Note that any keys beginning with `_` (underscore) are
    considered private and should be forward along as-is (this better allows
    e.g. `:current_py_cc_headers` to act as the underlying headers target it
    represents).
""",
        "platform_machine": """
:type: str

The {pep}`PEP 508` `platform_machine` marker
value for the target architecture, e.g. 'x86_64', 'aarch64'.

:::{versionadded} 2.3.0
:::
""",
        "platform_tag": """\
:type: str | None

The PEP 3149 / PEP 425 platform tag for extension modules, e.g.
'x86_64-linux-gnu', 'darwin', or 'win_amd64'.

:::{versionadded} 2.3.0
:::
""",
        "python_version": """
:type: str

The Python Major.Minor version.
""",
        "soabi": """\
:type: str

The SOABI tag for extension modules (see
[PEP 3149](https://peps.python.org/pep-3149/)), e.g.
'cpython-311-x86_64-linux-gnu' or 'cp311'.

:::{versionadded} 2.3.0
:::
""",
        "sys_platform": """
:type: str

The {pep}`0508` `sys_platform` marker value
for the target OS, e.g. 'linux', 'darwin', 'win32'.

:::{versionadded} 2.2.0
:::
""",
    },
)
