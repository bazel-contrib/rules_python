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

""

def _get_extra_pip_args_for_platform(ctx, extra_pip_args):
    """Returns the pip args for the given platform from the dict.

    Args:
        ctx: Current repository context.
        extra_pip_args: (string keyed string list dict): Extra pip arguments.

    Returns:
        List of arguments for the current platform.
    """

    os = ctx.os.name.replace(" ", "")
    arch = ctx.os.arch.replace(" ", "")

    # Check if there's an exact match.
    full_match = "{}_{}".format(os, arch)
    if full_match in extra_pip_args:
        return extra_pip_args[full_match]

    # Match on the os.
    os_match = "{}_*".format(os)
    if os_match in extra_pip_args:
        return extra_pip_args[os_match]

    # Match on the arch.
    arch_match = "*_{}".format(arch)
    if arch_match in extra_pip_args:
        return extra_pip_args[arch_match]

    # Wildcard match last to allow for a more specific match.
    if "*" in extra_pip_args:
        return extra_pip_args["*"]

    return []

def resolve_extra_pip_args(ctx, extra_pip_args, extra_pip_args_by_platform):
    """Resolves the given set of extra pip args to the list that should be used on the current platform.

    Args:
        ctx: Current repository or module context.
        extra_pip_args: (string list): Extra pip arguments.
        extra_pip_args_by_platform: (string keyed string list dict): Extra pip arguments keyed by platform.

    Returns:
        List of arguments for the current platform.
    """
    if len(extra_pip_args_by_platform):
        return _get_extra_pip_args_for_platform(ctx, extra_pip_args_by_platform)
    return extra_pip_args
