# Copyright 2019 The Bazel Authors. All rights reserved.
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
"""Versions of rules_python dependencies."""

# Currently used Bazel version. This version is what the rules here are tested
# against.
# LINT.IfChange(bazel_version)
BAZEL_VERSION = "8.x"
# LINT.ThenChange(//.bazelversion)

# This is the minimum supported bazel version, that we have some tests for.
# LINT.IfChange(minimum_bazel_version)
MINIMUM_BAZEL_VERSION = "7.4.1"
# LINT.ThenChange(//.bazelci/presubmit.yml:minimum_supported_version)

# Versions of Bazel which users should be able to use.
# Ensures we don't break backwards-compatibility,
# accidentally forcing users to update their LTS-supported bazel.
# These are the versions used when testing nested workspaces with
# rules_bazel_integration_test.
# LINT.IfChange(supported_bazel_versions)
SUPPORTED_BAZEL_VERSIONS = [
    BAZEL_VERSION,
    MINIMUM_BAZEL_VERSION,
]
# LINT.ThenChange(//MODULE.bazel:bazel_binaries)

def bazel_version_to_binary_label(version):
    return "@build_bazel_bazel_%s//:bazel_binary" % version.replace(".", "_")
