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

"""This file contains macros to be called during WORKSPACE evaluation."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", _http_archive = "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//python:versions.bzl", "MINOR_MAPPING", "TOOL_VERSIONS")
load("//python/private/pypi:deps.bzl", "pypi_deps")
load(":internal_config_repo.bzl", "internal_config_repo")
load(":pythons_hub.bzl", "hub_repo")

def http_archive(**kwargs):
    maybe(_http_archive, **kwargs)

def py_repositories():
    """Runtime dependencies that users must install.

    This function should be loaded and called in the user's `WORKSPACE`.
    With `bzlmod` enabled, this function is not needed since `MODULE.bazel` handles transitive deps.
    """
    maybe(
        internal_config_repo,
        name = "rules_python_internal",
    )
    maybe(
        hub_repo,
        name = "pythons_hub",
        minor_mapping = MINOR_MAPPING,
        default_python_version = "",
        toolchain_prefixes = [],
        toolchain_python_versions = [],
        toolchain_set_python_version_constraints = [],
        toolchain_user_repository_names = [],
        python_versions = sorted(TOOL_VERSIONS.keys()),
    )
    http_archive(
        name = "bazel_skylib",
        sha256 = "74d544d96f4a5bb630d465ca8bbcfe231e3594e5aae57e1edbf17a6eb3ca2506",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
        ],
    )
    http_archive(
        name = "rules_cc",
        urls = ["https://github.com/bazelbuild/rules_cc/releases/download/0.0.9/rules_cc-0.0.9.tar.gz"],
        sha256 = "2037875b9a4456dce4a79d112a8ae885bbc4aad968e6587dca6e64f3a0900cdf",
        strip_prefix = "rules_cc-0.0.9",
    )
    http_archive(
        name = "bazel_features",
        sha256 = "b4b145c19e08fd48337f53c383db46398d0a810002907ff0c590762d926e05be",
        strip_prefix = "bazel_features-1.18.0",
        url = "https://github.com/bazel-contrib/bazel_features/releases/download/v1.18.0/bazel_features-v1.18.0.tar.gz",
    )
    pypi_deps()
