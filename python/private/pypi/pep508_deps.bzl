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

load("@pythons_hub//:versions.bzl", "DEFAULT_PYTHON_VERSION", "MINOR_MAPPING")
load("//python/private:full_version.bzl", "full_version")
load("//python/private:normalize_name.bzl", "normalize_name")
load(":pep508_env.bzl", "env")
load(":pep508_evaluate.bzl", "evaluate")
load(":pep508_platform.bzl", "platform", "platform_from_str")
load(":pep508_requirement.bzl", "requirement")

def deps(
        name,
        *,
        requires_dist,
        platforms = [],
        extras = [],
        excludes = [],
        default_python_version = None,
        minor_mapping = MINOR_MAPPING):
    """Parse the RequiresDist from wheel METADATA

    Args:
        name: {type}`str` the name of the wheel.
        requires_dist: {type}`list[str]` the list of RequiresDist lines from the
            METADATA file.
        excludes: {type}`list[str]` what packages should we exclude.
        extras: {type}`list[str]` the requested extras to generate targets for.
        platforms: {type}`list[str]` the list of target platform strings.
        default_python_version: {type}`str` the host python version.
        minor_mapping: {type}`type[str, str]` the minor mapping to use when
            resolving to the full python version as DEFAULT_PYTHON_VERSION can by
            of format `3.x`.

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
    excludes = [name] + [normalize_name(x) for x in excludes]

    default_python_version = default_python_version or DEFAULT_PYTHON_VERSION
    if default_python_version:
        # if it is not bzlmod, then DEFAULT_PYTHON_VERSION may be unset
        default_python_version = full_version(
            version = default_python_version,
            minor_mapping = minor_mapping,
        )
    platforms = [
        platform_from_str(p, python_version = default_python_version)
        for p in platforms
    ]

    abis = sorted({p.abi: True for p in platforms if p.abi})
    if default_python_version and len(abis) > 1:
        _, _, tail = default_python_version.partition(".")
        default_abi = "cp3" + tail
    elif len(abis) > 1:
        fail(
            "all python versions need to be specified explicitly, got: {}".format(platforms),
        )
    else:
        default_abi = None

    reqs_by_name = {}

    for req in reqs:
        if req.name_ in excludes:
            continue

        reqs_by_name.setdefault(req.name, []).append(req)

    for name, reqs in reqs_by_name.items():
        _add_reqs(
            deps,
            deps_select,
            normalize_name(name),
            reqs,
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
        return "{}_{}".format(self.os, self.arch)

    return "{}_{}_{}".format(
        self.abi,
        self.os or "anyos",
        self.arch or "anyarch",
    )

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
    deps_select.setdefault(platform, {})[dep] = True

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

def _add_reqs(deps, deps_select, dep, reqs, *, extras, platforms, default_abi = None):
    for req in reqs:
        if not req.marker:
            _add(deps, deps_select, dep, None)
            return

    platforms_to_add = {}
    for plat in platforms:
        if plat in platforms_to_add:
            # marker evaluation is more expensive than this check
            continue

        added = False
        for extra in extras:
            if added:
                break

            for req in reqs:
                if evaluate(req.marker, env = env(target_platform = plat, extra = extra)):
                    platforms_to_add[plat] = True
                    added = True
                    break

    if len(platforms_to_add) == len(platforms):
        # the dep is in all target platforms, let's just add it to the regular
        # list
        _add(deps, deps_select, dep, None)
        return

    for plat in platforms_to_add:
        if default_abi:
            _add(deps, deps_select, dep, plat)
        if plat.abi == default_abi or not default_abi:
            _add(deps, deps_select, dep, platform(os = plat.os, arch = plat.arch))
