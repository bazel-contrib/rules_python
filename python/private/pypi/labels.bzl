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

"""Constants used by parts of pip_repository for naming libraries and wheels."""

load("//python/private:normalize_name.bzl", "normalize_name")

EXTRACTED_WHEEL_FILES = "extracted_whl_files"
WHEEL_FILE_PUBLIC_LABEL = "whl"
WHEEL_FILE_IMPL_LABEL = "_whl"
WHEEL_FILE = "whl_file"
PY_LIBRARY_PUBLIC_LABEL = "pkg"
PY_LIBRARY_IMPL_LABEL = "_pkg"
PY_SRCS_LABEL = "srcs"
DATA_LABEL = "data"
DIST_INFO_LABEL = "dist_info"
NODEPS_LABEL = "no_deps"

def extra_label(extra):
    """Return the label name for the target that includes an extra.

    Args:
        extra: {type}`str` the normalized name of the extra, an empty string
            means the base package without any extras.

    Returns:
        The target name, e.g. `[extra]`.
    """
    return "[{}]".format(extra)

def group_member(spec):
    """Normalize a member of a dependency group.

    Args:
        spec: {type}`str` the package name, e.g. `Foo`, or the package name
            with a single extra, e.g. `Foo[Bar]`.

    Returns:
        The normalized member, e.g. `foo` or `foo[bar]`.
    """
    name, _, extra = spec.partition("[")
    name = normalize_name(name.strip())
    extra = normalize_name(extra.partition("]")[0].strip()) if extra else ""
    return "{}[{}]".format(name, extra) if extra else name
