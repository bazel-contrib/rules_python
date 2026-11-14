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

def _labels(tmpl, requirement):
    name, bracket, extras = requirement.partition("[")
    name = normalize_name(name.strip())
    if not bracket:
        return [tmpl.format(name, PY_LIBRARY_PUBLIC_LABEL)]

    extras, _, _ = extras.partition("]")
    extras = sorted([
        normalize_name(extra.strip())
        for extra in extras.split(",")
        if extra.strip()
    ])
    return [tmpl.format(name, extra_label(extra)) for extra in extras or [""]]

def requirement_label(tmpl, requirement, *, fail = fail):
    """Return the label for a requirement in a hub repository.

    Args:
        tmpl: {type}`str` the label template with two `{}` placeholders for
            the package name and the target name.
        requirement: {type}`str` the name of the package with at most one
            extra, e.g. `foo`, `foo[]` or `foo[bar]`.
        fail: the function to call on errors, used in tests.

    Returns:
        {type}`str` the label of the `pkg` target if no extras are given, the
        label of the `[]` target if empty extras are given, or the label of
        the `[extra]` target if one extra is given.
    """
    labels = _labels(tmpl, requirement)
    if len(labels) > 1:
        fail("Only a single extra is supported by 'requirement', use 'requirements(\"{}\")' instead to get a list of labels.".format(requirement))

    return labels[0]

def requirement_labels(tmpl, *requirements):
    """Return the labels for requirements in a hub repository.

    Args:
        tmpl: {type}`str` the label template with two `{}` placeholders for
            the package name and the target name.
        *requirements: {type}`str` the names of the packages with optional
            extras, e.g. `foo`, `foo[]`, `foo[bar]` or `foo[bar,baz]`.

    Returns:
        {type}`list[str]` the labels for each requirement, with an `[extra]`
        label for each extra of a requirement. Each `[extra]` target includes
        the package.
    """
    return [
        label
        for requirement in requirements
        for label in _labels(tmpl, requirement)
    ]

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
