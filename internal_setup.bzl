# Copyright 2022 The Bazel Authors. All rights reserved.
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

"""Setup for rules_python tests and tools."""

load("@bazel_features//:deps.bzl", "bazel_features_deps")
load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")
load("@cgrindel_bazel_starlib//:deps.bzl", "bazel_starlib_dependencies")
load("@com_google_protobuf//:protobuf_deps.bzl", "protobuf_deps")
load("@rules_bazel_integration_test//bazel_integration_test:deps.bzl", "bazel_integration_test_rules_dependencies")
load("@rules_bazel_integration_test//bazel_integration_test:repo_defs.bzl", "bazel_binaries")
load("@rules_java//java:repositories.bzl", "rules_java_dependencies", "rules_java_toolchains")
load("@rules_proto//proto:repositories.bzl", "rules_proto_dependencies", "rules_proto_toolchains")
load("@rules_shell//shell:repositories.bzl", "rules_shell_dependencies", "rules_shell_toolchains")
load("//:version.bzl", "SUPPORTED_BAZEL_VERSIONS")
load("//python:versions.bzl", "MINOR_MAPPING", "TOOL_VERSIONS")
load("//python/private:internal_config_repo.bzl", "internal_config_repo")  # buildifier: disable=bzl-visibility
load("//python/private:pythons_hub.bzl", "hub_repo")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:deps.bzl", "pypi_deps")  # buildifier: disable=bzl-visibility

def rules_python_internal_setup():
    """Setup for rules_python tests and tools."""

    internal_config_repo(name = "rules_python_internal")
    hub_repo(
        name = "pythons_hub",
        minor_mapping = MINOR_MAPPING,
        default_python_version = "",
        toolchain_prefixes = [],
        toolchain_python_versions = [],
        toolchain_set_python_version_constraints = [],
        toolchain_user_repository_names = [],
        python_versions = sorted(TOOL_VERSIONS.keys()),
    )

    pypi_deps()

    bazel_skylib_workspace()

    rules_proto_dependencies()
    rules_proto_toolchains()

    protobuf_deps()

    rules_java_dependencies()
    rules_java_toolchains()

    bazel_integration_test_rules_dependencies()
    bazel_starlib_dependencies()
    bazel_binaries(versions = SUPPORTED_BAZEL_VERSIONS)
    bazel_features_deps()
    rules_shell_dependencies()
    rules_shell_toolchains()
