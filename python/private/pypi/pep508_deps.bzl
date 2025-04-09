# Copyright 2025 The Bazel Authors. All rights reserved.
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

"""This module is for implementing PEP508 compliant METADATA deps parsing.
"""

load("//python/private:normalize_name.bzl", "normalize_name")
load(":pep508_env.bzl", "env")
load(":pep508_evaluate.bzl", "evaluate")
load(":pep508_platform.bzl", "platform", "platform_from_str")
load(":pep508_requirement.bzl", "requirement")

_ALL_OS_VALUES = [
    "windows",
    "osx",
    "linux",
]
_ALL_ARCH_VALUES = [
    "aarch64",
    "ppc64",
    "ppc64le",
    "s390x",
    "x86_32",
    "x86_64",
]

def deps(name, *, requires_dist, platforms = [], extras = [], host_python_version = None):
    """Parse the RequiresDist from wheel METADATA

    Args:
        name: {type}`str` the name of the wheel.
        requires_dist: {type}`list[str]` the list of RequiresDist lines from the
            METADATA file.
        extras: {type}`list[str]` the requested extras to generate targets for.
        platforms: {type}`list[str]` the list of target platform strings.
        host_python_version: {type}`str` the host python version.

    Returns:
        A struct with attributes:
        * deps: {type}`list[str]` dependencies to include unconditionally.
        * deps_select: {type}`dict[str, list[str]]` dependencies to include on particular
              subset of target platforms.
    """
    reqs = sorted(
        [requirement(r) for r in requires_dist],
        key = lambda x: "{}:{}:".format(x.name, sorted(x.extras), x.marker),
    )
    deps = {}
    deps_select = {}
    name = normalize_name(name)
    want_extras = _resolve_extras(name, reqs, extras)

    # drop self edges
    reqs = [r for r in reqs if r.name != name]

    platforms = [
        platform_from_str(p, python_version = host_python_version)
        for p in platforms
    ] or [
        platform_from_str("", python_version = host_python_version),
    ]

    abis = sorted({p.abi: True for p in platforms if p.abi})
    if host_python_version and len(abis) > 1:
        _, _, minor_version = host_python_version.partition(".")
        minor_version, _, _ = minor_version.partition(".")
        default_abi = "cp3" + minor_version
    elif len(abis) > 1:
        fail(
            "all python versions need to be specified explicitly, got: {}".format(platforms),
        )
    else:
        default_abi = None

    for req in reqs:
        _add_req(
            deps,
            deps_select,
            req,
            extras = want_extras,
            platforms = platforms,
            default_abi = default_abi,
        )

    return struct(
        deps = sorted(deps),
        deps_select = {
            _platform_str(p): sorted(deps)
            for p, deps in deps_select.items()
        },
    )

def _platform_str(self):
    if self.abi == None:
        if not self.os and not self.arch:
            return "//conditions:default"
        elif not self.arch:
            return "@platforms//os:{}".format(self.os)
        else:
            return "{}_{}".format(self.os, self.arch)

    minor_version = self.abi[3:]
    if self.arch == None and self.os == None:
        return str(Label("//python/config_settings:is_python_3.{}".format(minor_version)))

    return "cp3{}_{}_{}".format(
        minor_version,
        self.os or "anyos",
        self.arch or "anyarch",
    )

def _platform_specializations(self, cpu_values = _ALL_ARCH_VALUES, os_values = _ALL_OS_VALUES):
    """Return the platform itself and all its unambiguous specializations.

    For more info about specializations see
    https://bazel.build/docs/configurable-attributes
    """
    specializations = []
    specializations.append(self)
    if self.arch == None:
        specializations.extend([
            platform(os = self.os, arch = arch, abi = self.abi)
            for arch in cpu_values
        ])
    if self.os == None:
        specializations.extend([
            platform(os = os, arch = self.arch, abi = self.abi)
            for os in os_values
        ])
    if self.os == None and self.arch == None:
        specializations.extend([
            platform(os = os, arch = arch, abi = self.abi)
            for os in os_values
            for arch in cpu_values
        ])
    return specializations

def _add(deps, deps_select, dep, platform):
    dep = normalize_name(dep)

    if platform == None:
        deps[dep] = True

        # If the dep is in the platform-specific list, remove it from the select.
        pop_keys = []
        for p, _deps in deps_select.items():
            if dep not in _deps:
                continue

            _deps.pop(dep)
            if not _deps:
                pop_keys.append(p)

        for p in pop_keys:
            deps_select.pop(p)
        return

    if dep in deps:
        # If the dep is already in the main dependency list, no need to add it in the
        # platform-specific dependency list.
        return

    # Add the platform-specific branch
    deps_select.setdefault(platform, {})

    # Add the dep to specializations of the given platform if they
    # exist in the select statement.
    for p in _platform_specializations(platform):
        if p not in deps_select:
            continue

        deps_select[p][dep] = True

    if len(deps_select[platform]) == 1:
        # We are adding a new item to the select and we need to ensure that
        # existing dependencies from less specialized platforms are propagated
        # to the newly added dependency set.
        for p, _deps in deps_select.items():
            # Check if the existing platform overlaps with the given platform
            if p == platform or platform not in _platform_specializations(p):
                continue

            deps_select[platform].update(_deps)

def _maybe_add_common_dep(deps, deps_select, platforms, dep):
    abis = sorted({p.abi: True for p in platforms if p.abi})
    if len(abis) < 2:
        return

    platforms = [platform()] + [
        platform(abi = abi)
        for abi in abis
    ]

    # If the dep is targeting all target python versions, lets add it to
    # the common dependency list to simplify the select statements.
    for p in platforms:
        if p not in deps_select:
            return

        if dep not in deps_select[p]:
            return

    # All of the python version-specific branches have the dep, so lets add
    # it to the common deps.
    deps[dep] = True
    for p in platforms:
        deps_select[p].pop(dep)
        if not deps_select[p]:
            deps_select.pop(p)

def _resolve_extras(self_name, reqs, extras):
    """Resolve extras which are due to depending on self[some_other_extra].

    Some packages may have cyclic dependencies resulting from extras being used, one example is
    `etils`, where we have one set of extras as aliases for other extras
    and we have an extra called 'all' that includes all other extras.

    Example: github.com/google/etils/blob/a0b71032095db14acf6b33516bca6d885fe09e35/pyproject.toml#L32.

    When the `requirements.txt` is generated by `pip-tools`, then it is likely that
    this step is not needed, but for other `requirements.txt` files this may be useful.

    NOTE @aignas 2023-12-08: the extra resolution is not platform dependent,
    but in order for it to become platform dependent we would have to have
    separate targets for each extra in extras.
    """

    # Resolve any extra extras due to self-edges, empty string means no
    # extras The empty string in the set is just a way to make the handling
    # of no extras and a single extra easier and having a set of {"", "foo"}
    # is equivalent to having {"foo"}.
    extras = extras or [""]

    self_reqs = []
    for req in reqs:
        if req.name != self_name:
            continue

        if req.marker == None:
            # I am pretty sure we cannot reach this code as it does not
            # make sense to specify packages in this way, but since it is
            # easy to handle, lets do it.
            #
            # TODO @aignas 2023-12-08: add a test
            extras = extras + req.extras
        else:
            # process these in a separate loop
            self_reqs.append(req)

    # A double loop is not strictly optimal, but always correct without recursion
    for req in self_reqs:
        if [True for extra in extras if evaluate(req.marker, env = {"extra": extra})]:
            extras = extras + req.extras
        else:
            continue

        # Iterate through all packages to ensure that we include all of the extras from previously
        # visited packages.
        for req_ in self_reqs:
            if [True for extra in extras if evaluate(req.marker, env = {"extra": extra})]:
                extras = extras + req_.extras

    # Poor mans set
    return sorted({x: None for x in extras})

def _add_req(deps, deps_select, req, *, extras, platforms, default_abi = None):
    if not req.marker:
        _add(deps, deps_select, req.name, None)
        return

    # NOTE @aignas 2023-12-08: in order to have reasonable select statements
    # we do have to have some parsing of the markers, so it begs the question
    # if packaging should be reimplemented in Starlark to have the best solution
    # for now we will implement it in Python and see what the best parsing result
    # can be before making this decision.
    match_os = len([
        tag
        for tag in [
            "os_name",
            "sys_platform",
            "platform_system",
        ]
        if tag in req.marker
    ]) > 0
    match_arch = "platform_machine" in req.marker
    match_version = "version" in req.marker

    if not (match_os or match_arch or match_version):
        if [
            True
            for extra in extras
            for p in platforms
            if evaluate(
                req.marker,
                env = env(
                    target_platform = p,
                    extra = extra,
                ),
            )
        ]:
            _add(deps, deps_select, req.name, None)
        return

    for plat in platforms:
        if not [
            True
            for extra in extras
            if evaluate(
                req.marker,
                env = env(
                    target_platform = plat,
                    extra = extra,
                ),
            )
        ]:
            continue

        if match_arch and default_abi:
            _add(deps, deps_select, req.name, plat)
            if plat.abi == default_abi:
                _add(deps, deps_select, req.name, platform(os = plat.os, arch = plat.arch))
        elif match_arch:
            _add(deps, deps_select, req.name, platform(os = plat.os, arch = plat.arch))
        elif match_os and default_abi:
            _add(deps, deps_select, req.name, platform(os = plat.os, abi = plat.abi))
            if plat.abi == default_abi:
                _add(deps, deps_select, req.name, platform(os = plat.os))
        elif match_os:
            _add(deps, deps_select, req.name, platform(os = plat.os))
        elif match_version and default_abi:
            _add(deps, deps_select, req.name, platform(abi = plat.abi))
            if plat.abi == default_abi:
                _add(deps, deps_select, req.name, platform())
        elif match_version:
            _add(deps, deps_select, req.name, None)
        else:
            fail("BUG: {} support is not implemented".format(req.marker))

    _maybe_add_common_dep(deps, deps_select, platforms, req.name)
