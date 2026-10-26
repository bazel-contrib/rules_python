# Copyright 2017 The Bazel Authors. All rights reserved.
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
"""Rules for pip integration.

This contains a set of rules that are used to support inclusion of third-party
dependencies via fully locked `requirements.txt` files. Some of the exported
symbols should not be used and they are either undocumented here or marked as
for internal use only.

If you are using a bazel version 7 or above with `bzlmod`, you should only care
about the {bzl:obj}`compile_pip_requirements` macro exposed in this file. The
rest of the symbols are for legacy `WORKSPACE` setups.
"""

load("//python/private:normalize_name.bzl", "normalize_name")
load("//python/private/pypi:multi_pip_parse.bzl", _multi_pip_parse = "multi_pip_parse")
load("//python/private/pypi:package_annotation.bzl", _package_annotation = "package_annotation")
load("//python/private/pypi:pip_compile.bzl", "pip_compile")
load("//python/private/pypi:pip_repository.bzl", "pip_repository")
load("//python/private/pypi:py_installed_wheel_info.bzl", _PyInstalledWheelInfo = "PyInstalledWheelInfo")
load(
    "//python/private/pypi:py_wheel_extract_files.bzl",
    _py_wheel_extract_files = "py_wheel_extract_files",
    _wheel_glob = "wheel_glob",
)
load("//python/private/pypi:py_wheel_headers.bzl", _py_wheel_headers = "py_wheel_headers")
load("//python/private/pypi:py_wheel_transform.bzl", _py_wheel_transform = "py_wheel_transform")
load("//python/private/pypi:whl_library_alias.bzl", _whl_library_alias = "whl_library_alias")
load("//python/private/whl_filegroup:whl_filegroup.bzl", _whl_filegroup = "whl_filegroup")

PyInstalledWheelInfo = _PyInstalledWheelInfo
compile_pip_requirements = pip_compile
package_annotation = _package_annotation
pip_parse = pip_repository
py_wheel_extract_files = _py_wheel_extract_files
py_wheel_headers = _py_wheel_headers
py_wheel_transform = _py_wheel_transform
wheel_glob = _wheel_glob
whl_filegroup = _whl_filegroup

# Extra utilities visible to rules_python users.
pip_utils = struct(
    normalize_name = normalize_name,
)

# The following are only exported here because they are used from
# multi_toolchain_aliases repository_rule, not intended for public use.
#
# See ./private/toolchains_repo.bzl
multi_pip_parse = _multi_pip_parse
whl_library_alias = _whl_library_alias
