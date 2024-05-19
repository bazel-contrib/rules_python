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

"""Requirements parsing for whl_library creation.

Use cases that the code needs to cover:
* A single requirements_lock file that is used for the host platform.
* Per-OS requirements_lock files that are used for the host platform.
* A target platform specific requirements_lock that is used with extra
  pip arguments with --platform, etc and download_only = True.

In the last case only a single `requirements_lock` file is allowed, in all
other cases we assume that there may be a desire to resolve the requirements
file for the host platform to be backwards compatible with the legacy
behavior.
"""

load("//python/pip_install:requirements_parser.bzl", "parse")
load(":normalize_name.bzl", "normalize_name")
load(":pypi_index_sources.bzl", "get_simpleapi_sources")
load(":whl_target_platforms.bzl", "whl_target_platforms")

# This includes the vendored _translate_cpu and _translate_os from
# @platforms//host:extension.bzl at version 0.0.9 so that we don't
# force the users to depend on it.

def _translate_cpu(arch):
    if arch in ["i386", "i486", "i586", "i686", "i786", "x86"]:
        return "x86_32"
    if arch in ["amd64", "x86_64", "x64"]:
        return "x86_64"
    if arch in ["ppc", "ppc64", "ppc64le"]:
        return "ppc"
    if arch in ["arm", "armv7l"]:
        return "arm"
    if arch in ["aarch64"]:
        return "aarch64"
    if arch in ["s390x", "s390"]:
        return "s390x"
    if arch in ["mips64el", "mips64"]:
        return "mips64"
    if arch in ["riscv64"]:
        return "riscv64"
    return arch

def _translate_os(os):
    if os.startswith("mac os"):
        return "osx"
    if os.startswith("freebsd"):
        return "freebsd"
    if os.startswith("openbsd"):
        return "openbsd"
    if os.startswith("linux"):
        return "linux"
    if os.startswith("windows"):
        return "windows"
    return os

# TODO @aignas 2024-05-13: consider using the same platform tags as are used in
# the //python:versions.bzl
DEFAULT_PLATFORMS = [
    "linux_aarch64",
    "linux_arm",
    "linux_ppc",
    "linux_s390x",
    "linux_x86_64",
    "osx_aarch64",
    "osx_x86_64",
    "windows_x86_64",
]

def _default_platforms(*, filter):
    if not filter:
        fail("Must specific a filter string, got: {}".format(filter))

    sanitized = filter.replace("*", "").replace("_", "")
    if sanitized and not sanitized.isalnum():
        fail("The platform filter can only contain '*', '_' and alphanumerics")

    if "*" in filter:
        prefix = filter.rstrip("*")
        if "*" in prefix:
            fail("The filter can only contain '*' at the end of it")

        if not prefix:
            return DEFAULT_PLATFORMS

        return [p for p in DEFAULT_PLATFORMS if p.startswith(prefix)]
    else:
        return [p for p in DEFAULT_PLATFORMS if filter in p]

def _platforms_from_args(extra_pip_args):
    platform_values = []

    for arg in extra_pip_args:
        if platform_values and platform_values[-1] == "":
            platform_values[-1] = arg
            continue

        if arg == "--platform":
            platform_values.append("")
            continue

        if not arg.startswith("--platform"):
            continue

        _, _, plat = arg.partition("=")
        if not plat:
            _, _, plat = arg.partition(" ")
        if plat:
            platform_values.append(plat)
        else:
            platform_values.append("")

    if not platform_values:
        return []

    platforms = {
        p.target_platform: None
        for arg in platform_values
        for p in whl_target_platforms(arg)
    }
    return list(platforms.keys())

def parse_requirements(
        ctx,
        *,
        requirements_by_platform = {},
        requirements_osx = None,
        requirements_linux = None,
        requirements_lock = None,
        requirements_windows = None,
        extra_pip_args = [],
        fail_fn = fail):
    """Get the requirements with platforms that the requirements apply to.

    Args:
        ctx: A context that has .read function that would read contents from a label.
        requirements_by_platform (label_keyed_string_dict): a way to have
            different package versions (or different packages) for different
            os, arch combinations.
        requirements_osx (label): The requirements file for the osx OS.
        requirements_linux (label): The requirements file for the linux OS.
        requirements_lock (label): The requirements file for all OSes, or used as a fallback.
        requirements_windows (label): The requirements file for windows OS.
        extra_pip_args (string list): Extra pip arguments to perform extra validations and to
            be joined with args fined in files.
        fail_fn (Callable[[str], None]): A failure function used in testing failure cases.

    Returns:
        A tuple where the first element a dict of dicts where the first key is
        the normalized distribution name (with underscores) and the second key
        is the requirement_line, then value and the keys are structs with the
        following attributes:
         * distribution: The non-normalized distribution name.
         * srcs: The Simple API downloadable source list.
         * requirement_line: The original requirement line.
         * target_platforms: The list of target platforms that this package is for.

        The second element is extra_pip_args should be passed to `whl_library`.
    """
    if not (
        requirements_lock or
        requirements_linux or
        requirements_osx or
        requirements_windows or
        requirements_by_platform
    ):
        fail_fn(
            "A 'requirements_lock' attribute must be specified, a platform-specific lockfiles " +
            "via 'requirements_by_platform' or an os-specific lockfiles must be specified " +
            "via 'requirements_*' attributes",
        )
        return None

    platforms = _platforms_from_args(extra_pip_args)

    if platforms:
        lock_files = [
            f
            for f in [
                requirements_lock,
                requirements_linux,
                requirements_osx,
                requirements_windows,
            ] + list(requirements_by_platform.keys())
            if f
        ]

        if len(lock_files) > 1:
            # If the --platform argument is used, check that we are using
            # a single `requirements_lock` file instead of the OS specific ones as that is
            # the only correct way to use the API.
            fail_fn("only a single 'requirements_lock' file can be used when using '--platform' pip argument, consider specifying it via 'requirements_lock' attribute")
            return None

        files_by_platform = [
            (lock_files[0], platforms),
        ]
    else:
        files_by_platform = {
            file: [
                platform
                for filter_or_platform in specifier.split(",")
                for platform in (_default_platforms(filter = filter_or_platform) if filter_or_platform.endswith("*") else [filter_or_platform])
            ]
            for file, specifier in requirements_by_platform.items()
        }.items()

        for f in [
            # If the users need a greater span of the platforms, they should consider
            # using the 'requirements_by_platform' attribute.
            (requirements_linux, _default_platforms(filter = "linux_*")),
            (requirements_osx, _default_platforms(filter = "osx_*")),
            (requirements_windows, _default_platforms(filter = "windows_*")),
            (requirements_lock, None),
        ]:
            if f[0]:
                files_by_platform.append(f)

    configured_platforms = {}

    options = {}
    requirements = {}
    for file, plats in files_by_platform:
        if plats:
            for p in plats:
                if p in configured_platforms:
                    fail_fn(
                        "Expected the platform '{}' to be map only to a single requirements file, but got multiple: '{}', '{}'".format(
                            p,
                            configured_platforms[p],
                            file,
                        ),
                    )
                    return None
                configured_platforms[p] = file
        else:
            plats = [
                p
                for p in DEFAULT_PLATFORMS
                if p not in configured_platforms
            ]

        contents = ctx.read(file)

        # Parse the requirements file directly in starlark to get the information
        # needed for the whl_libary declarations later.
        parse_result = parse(contents)

        # Replicate a surprising behavior that WORKSPACE builds allowed:
        # Defining a repo with the same name multiple times, but only the last
        # definition is respected.
        # The requirement lines might have duplicate names because lines for extras
        # are returned as just the base package name. e.g., `foo[bar]` results
        # in an entry like `("foo", "foo[bar] == 1.0 ...")`.
        requirements_dict = {
            normalize_name(entry[0]): entry
            for entry in sorted(
                parse_result.requirements,
                # Get the longest match and fallback to original WORKSPACE sorting,
                # which should get us the entry with most extras.
                #
                # FIXME @aignas 2024-05-13: The correct behaviour might be to get an
                # entry with all aggregated extras, but it is unclear if we
                # should do this now.
                key = lambda x: (len(x[1].partition("==")[0]), x),
            )
        }.values()

        tokenized_options = []
        for opt in parse_result.options:
            for p in opt.split(" "):
                tokenized_options.append(p)

        pip_args = tokenized_options + extra_pip_args
        for p in plats:
            requirements[p] = requirements_dict
            options[p] = pip_args

    requirements_by_platform = {}
    for target_platform, reqs_ in requirements.items():
        extra_pip_args = options[target_platform]

        for distribution, requirement_line in reqs_:
            for_whl = requirements_by_platform.setdefault(
                normalize_name(distribution),
                {},
            )

            for_req = for_whl.setdefault(
                (requirement_line, ",".join(extra_pip_args)),
                struct(
                    distribution = distribution,
                    srcs = get_simpleapi_sources(requirement_line),
                    requirement_line = requirement_line,
                    target_platforms = [],
                    extra_pip_args = extra_pip_args,
                    download = len(platforms) > 0,
                ),
            )
            for_req.target_platforms.append(target_platform)

    return {
        whl_name: [
            struct(
                distribution = r.distribution,
                srcs = r.srcs,
                requirement_line = r.requirement_line,
                target_platforms = sorted(r.target_platforms),
                extra_pip_args = r.extra_pip_args,
                download = r.download,
            )
            for r in sorted(reqs.values(), key = lambda r: r.requirement_line)
        ]
        for whl_name, reqs in requirements_by_platform.items()
    }

def select_requirement(requirements, *, platform):
    """A simple function to get a requirement for a particular platform.

    Args:
        requirements (list[struct]): The list of requirements as returned by
            the `parse_requirements` function above.
        platform (str): The host platform. Usually an output of the
        `host_platform` function.

    Returns:
        None if not found or a struct returned as one of the values in the
        parse_requirements function. The requirement that should be downloaded
        by the host platform will be returned.
    """
    maybe_requirement = [
        req
        for req in requirements
        if platform in req.target_platforms or req.download
    ]
    if not maybe_requirement:
        # Sometimes the package is not present for host platform if there
        # are whls specified only in particular requirements files, in that
        # case just continue, however, if the download_only flag is set up,
        # then the user can also specify the target platform of the wheel
        # packages they want to download, in that case there will be always
        # a requirement here, so we will not be in this code branch.
        return None

    return maybe_requirement[0]

def host_platform(repository_os):
    """Return a string representation of the repository OS.

    Args:
        repository_os (struct): The `module_ctx.os` or `repository_ctx.os` attribute.
            See https://bazel.build/rules/lib/builtins/repository_os.html

    Returns:
        The string representation of the platform that we can later used in the `pip`
        machinery.
    """
    return "{}_{}".format(
        _translate_os(repository_os.name.lower()),
        _translate_cpu(repository_os.arch.lower()),
    )
