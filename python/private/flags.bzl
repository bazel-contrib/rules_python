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

"""Values and helpers for flags.

NOTE: The transitive loads of this should be kept minimal. This avoids loading
unnecessary files when all that are needed are flag definitions.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//python/private:enum.bzl", "enum")

def _precompile_flag_get_effective_value(ctx):
    value = ctx.attr._precompile_flag[BuildSettingInfo].value
    if value == PrecompileFlag.AUTO:
        value = PrecompileFlag.DISABLED
    return value

# Determines if Python source files should be compiled at build time.
#
# NOTE: The flag value is overridden by the target-level attribute, except
# for the case of `force_enabled` and `forced_disabled`.
# buildifier: disable=name-conventions
PrecompileFlag = enum(
    # Automatically decide the effective value based on environment,
    # target platform, etc.
    AUTO = "auto",
    # Compile Python source files at build time. Note that
    # --precompile_add_to_runfiles affects how the compiled files are included
    # into a downstream binary.
    ENABLED = "enabled",
    # Don't compile Python source files at build time.
    DISABLED = "disabled",
    # Compile Python source files, but only if they're a generated file.
    IF_GENERATED_SOURCE = "if_generated_source",
    # Like `enabled`, except overrides target-level setting. This is mostly
    # useful for development, testing enabling precompilation more broadly, or
    # as an escape hatch if build-time compiling is not available.
    FORCE_ENABLED = "force_enabled",
    # Like `disabled`, except overrides target-level setting. This is useful
    # useful for development, testing enabling precompilation more broadly, or
    # as an escape hatch if build-time compiling is not available.
    FORCE_DISABLED = "force_disabled",
    get_effective_value = _precompile_flag_get_effective_value,
)

# Determines if, when a source file is compiled, if the source file is kept
# in the resulting output or not.
# buildifier: disable=name-conventions
PrecompileSourceRetentionFlag = enum(
    # Include the original py source in the output.
    KEEP_SOURCE = "keep_source",
    # Don't include the original py source.
    OMIT_SOURCE = "omit_source",
    # Keep the original py source if it's a regular source file, but omit it
    # if it's a generated file.
    OMIT_IF_GENERATED_SOURCE = "omit_if_generated_source",
)

# Determines if a target adds its compiled files to its runfiles. When a target
# compiles its files, but doesn't add them to its own runfiles, it relies on
# a downstream target to retrieve them from `PyInfo.transitive_pyc_files`
# buildifier: disable=name-conventions
PrecompileAddToRunfilesFlag = enum(
    # Always include the compiled files in the target's runfiles.
    ALWAYS = "always",
    # Don't include the compiled files in the target's runfiles; they are
    # still added to `PyInfo.transitive_pyc_files`. See also:
    # `py_binary.pyc_collection` attribute. This is useful for allowing
    # incrementally enabling precompilation on a per-binary basis.
    DECIDED_ELSEWHERE = "decided_elsewhere",
)

# Determine if `py_binary` collects transitive pyc files.
# NOTE: This flag is only respect if `py_binary.pyc_collection` is `inherit`.
# buildifier: disable=name-conventions
PycCollectionFlag = enum(
    # Include `PyInfo.transitive_pyc_files` as part of the binary.
    INCLUDE_PYC = "include_pyc",
    # Don't include `PyInfo.transitive_pyc_files` as part of the binary.
    DISABLED = "disabled",
)
