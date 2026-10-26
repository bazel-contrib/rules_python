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

"""Package annotation API for WORKSPACE setups."""

def package_annotation(
        additive_build_content = None,
        copy_files = {},
        copy_executables = {},
        data = [],
        data_exclude_glob = [],
        filegroups = {},
        sdist_build_deps = [],
        sdist_config_settings = {},
        site_paths = [],
        srcs_exclude_glob = []):
    """Annotations to apply to the BUILD file content from package generated from a `pip_repository` rule.

    [cf]: https://github.com/bazelbuild/bazel-skylib/blob/main/docs/copy_file_doc.md

    :::{versionchanged} VERSION_NEXT_FEATURE
    Added the `filegroups`, `sdist_build_deps`, `sdist_config_settings`, and
    `site_paths` parameters.
    :::

    Args:
        additive_build_content (str, optional): Raw text to add to the generated `BUILD` file of a package.
        copy_files (dict, optional): A mapping of `src` and `out` files for [@bazel_skylib//rules:copy_file.bzl][cf]
        copy_executables (dict, optional): A mapping of `src` and `out` files for
            [@bazel_skylib//rules:copy_file.bzl][cf]. Targets generated here will also be flagged as
            executable.
        data (list, optional): A list of labels to add as `data` dependencies to the generated `py_library` target.
        data_exclude_glob (list, optional): A list of exclude glob patterns to add as `data` to the generated
            `py_library` target.
        filegroups (dict, optional): A mapping of filegroup target names to glob patterns (or include/exclude dicts).
        sdist_build_deps (list, optional): Explicit build dependency labels for `py_sdist_wheel` when building an sdist in an action.
        sdist_config_settings (dict, optional): PEP 517 `--config-settings` key/value pairs for `py_sdist_wheel`.
        site_paths (list, optional): Override predicted `site-packages/` paths when building an sdist in an action.
        srcs_exclude_glob (list, optional): A list of labels to add as `srcs` to the generated `py_library` target.

    Returns:
        str: A json encoded string of the provided content.
    """
    optional_fields = {}
    for k, val in [
        ("filegroups", filegroups),
        ("sdist_build_deps", sdist_build_deps),
        ("sdist_config_settings", sdist_config_settings),
        ("site_paths", site_paths),
    ]:
        if val:
            optional_fields[k] = val
    return json.encode(struct(
        additive_build_content = additive_build_content,
        copy_files = copy_files,
        copy_executables = copy_executables,
        data = data,
        data_exclude_glob = data_exclude_glob,
        srcs_exclude_glob = srcs_exclude_glob,
        **optional_fields
    ))
