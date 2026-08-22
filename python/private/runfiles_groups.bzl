# Copyright 2026 The Bazel Authors. All rights reserved.
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
"""Support for emitting `RunfilesGroupInfo` (rules_runfiles_group).

The provider (see https://github.com/bazel-contrib/rules_runfiles_group)
splits a binary's runfiles into named groups so that packaging rules can
produce layered artifacts (e.g. container images with a shared interpreter
layer and one layer per third-party dependency).

How it works:

* Only `py_binary` / `py_test` (and `py_runtime`, whose runfiles are one
  trivial group) emit the public `RunfilesGroupInfo`. Its contract is that
  unioning all groups yields exactly `DefaultInfo.default_runfiles`, and at
  the binary level rules_python can guarantee that.
* `py_library` participates through the private {obj}`PyRunfilesGroupsInfo`
  provider: it references its dependencies' entry depsets and adds one entry
  for the files it contributes to a consuming binary (sources, pyc files,
  and plain data files). It's private because a library's sources are *not*
  in its own runfiles (they reach the binary via `PyInfo`), so the entries
  only mean something under rules_python's own aggregation. Publishing them
  as `RunfilesGroupInfo` would hand a foreign consumer groups claiming files
  it never adds.
* Libraries that come from PyPI (detected via their `*.dist-info/METADATA`
  file) use a stable `rules_python#pypi/<name>` group name; other libraries
  are per-target groups named by their Label.
* The binary adds three groups of its own: `rules_python#runtime` (the
  interpreter and stdlib), `rules_python#venv` (the binary-specific venv
  symlinks and support files), and `rules_python#app` (the binary's own
  sources, executable, bootstrap and build data), which it names as the
  `executable_group`.

Emission is gated by two flags: the ecosystem-wide
`@rules_runfiles_group//runfiles_group:enabled` switch, and
{obj}`--runfiles_groups`, whose default (`auto`) follows the ecosystem
switch and whose explicit values override it for rules_python only.

The feature requires Bazel 9+. On older versions, Bazel's autoload machinery
can't load rules_runfiles_group from rules_python (see the shim in
internal_config_repo.bzl), so both flags are inert no-ops there.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "@rules_python_internal//:runfiles_groups_shim.bzl",
    "ENABLED_FLAG_LABEL",
    "RUNFILES_GROUPS_AVAILABLE",
    "RunfilesGroupInfo",
    "runfiles_groups",
)
load(":flags.bzl", "PrecompileFlag", "RunfilesGroupsFlag")
load(":py_info.bzl", "PyInfo")
load(":py_internal.bzl", "py_internal")
load(":reexports.bzl", "BuiltinPyInfo")

# Label of the ecosystem-wide emission switch. Rules declare an attribute
# named `_runfiles_group_enabled` pointing at it (the name the upstream
# `runfiles_groups.is_enabled()` reads), in whatever attribute style the
# rule uses. On Bazel versions where the feature is unavailable, the shim
# points this at the `//python:none` sentinel instead.
RUNFILES_GROUP_ENABLED_LABEL = str(Label(ENABLED_FLAG_LABEL))

# String-named groups several targets contribute to. Strings share one
# namespace across every ruleset merged into a binary, so they carry the
# module name as a prefix. Per-target groups use their Label instead (free,
# globally unique, no prefix needed).
RUNTIME_GROUP = "rules_python#runtime"
VENV_GROUP = "rules_python#venv"
APP_GROUP = "rules_python#app"

_PYPI_GROUP_PREFIX = "rules_python#pypi/"

# Merge affinity stamped on the groups rules_python produces. Under merge
# pressure, packagers prefer merging groups that share an affinity, keeping
# Python groups together instead of interleaving them with other rulesets'
# groups.
_AFFINITY = "rules_python"

# Ranks: runtime < pypi deps < venv < first-party libraries < app.
# Literal values of the runfiles_groups.RANK_* anchors: they can't be read at
# load time because the shim stubs the module out on Bazel versions where the
# feature is unavailable.
_RUNTIME_RANK = -1000  # runfiles_groups.RANK_FOUNDATION
_PYPI_RANK = -100  # runfiles_groups.RANK_SHARED_DEPS
_VENV_RANK = -10
_LIBRARY_RANK = -1
_APP_RANK = 0  # runfiles_groups.RANK_EXECUTABLE

PyRunfilesGroupsInfo = provider(
    doc = """\
**INTERNAL rules_python provider. Do not use.**

Runfiles group entries a target contributes to a consuming `py_binary` /
`py_test`. This intentionally isn't `RunfilesGroupInfo`: the entries include
sources that travel via `PyInfo` rather than the target's own runfiles, so
they only satisfy the public provider's union contract once a binary
aggregates them.
""",
    fields = {
        "entries": """\
depset of `runfiles_groups.entry()` values, order = "default": this target's
own entries plus, transitively, its dependencies'.
""",
    },
)

def is_enabled(ctx):
    """Whether this rule should emit / propagate runfiles group entries.

    Args:
        ctx: rule ctx; must have the `_runfiles_groups_flag` and (upstream)
            `_runfiles_group_enabled` attributes.

    Returns:
        bool.
    """
    if not RUNFILES_GROUPS_AVAILABLE:
        return False
    value = ctx.attr._runfiles_groups_flag[BuildSettingInfo].value
    if value == RunfilesGroupsFlag.ENABLED:
        return True
    if value == RunfilesGroupsFlag.DISABLED:
        return False

    # auto: follow the ecosystem-wide switch.
    return runfiles_groups.is_enabled(ctx)

def pyc_collection_enabled_by_default(ctx):
    """Whether a binary with `pyc_collection = "inherit"` includes pyc files.

    This mirrors `PycCollectionAttr.is_pyc_collection_enabled`, but only
    depends on the configuration (not on binary-level attributes), so
    `py_library` can compute which of the implicit pyc / pyc-source files a
    consuming binary in the same configuration will select.

    Args:
        ctx: rule ctx; must have the `_precompile_flag` attribute.

    Returns:
        bool.
    """
    return PrecompileFlag.get_effective_value(ctx) in (
        PrecompileFlag.ENABLED,
        PrecompileFlag.FORCE_ENABLED,
    )

def runtime_entry(runfiles):
    """The interpreter + stdlib group entry.

    Args:
        runfiles: runfiles; the runtime's contribution to the binary.

    Returns:
        A group entry.
    """
    return runfiles_groups.entry(
        name = RUNTIME_GROUP,
        content = runfiles,
        kind = "foundation",
        rank = _RUNTIME_RANK,
        do_not_merge = True,
        merge_affinity = _AFFINITY,
    )

def venv_entry(runfiles):
    """The binary-specific venv group entry.

    Holds the site-packages symlinks and small generated files (pth, site
    init, pyvenv.cfg). These change whenever the dependency closure changes,
    but are cheap, so they get their own layer late in the ordering.

    Args:
        runfiles: runfiles; the venv files.

    Returns:
        A group entry.
    """
    return runfiles_groups.entry(
        name = VENV_GROUP,
        content = runfiles,
        rank = _VENV_RANK,
        merge_affinity = _AFFINITY,
    )

def app_entry(runfiles):
    """The binary's own group entry (code, executable, bootstrap, build data).

    The binary names this group as the provider's `executable_group`.

    Args:
        runfiles: runfiles; the binary's own contribution.

    Returns:
        A group entry.
    """
    return runfiles_groups.entry(
        name = APP_GROUP,
        content = runfiles,
        kind = "first_party",
        rank = _APP_RANK,
        merge_affinity = _AFFINITY,
    )

def library_entry(ctx, pypi_package, files):
    """A py_library's own group entry.

    Args:
        ctx: The rule ctx.
        pypi_package: str | None; the normalized PyPI package name, if this
            library is a PyPI-provided package.
        files: depset of File; the library's contribution to a consuming
            binary (sources, pyc files, plain data files).

    Returns:
        A group entry.
    """
    if pypi_package:
        # The whl repo naming (`<prefix>_<name>_<sha>`) is an implementation
        # detail and unstable, so use the normalized package name instead.
        # A wheel's srcs/data may be spread over several targets; all of
        # them contribute to the one package group, and two versions of one
        # package fold together rather than one silently winning.
        return runfiles_groups.entry(
            name = _PYPI_GROUP_PREFIX + pypi_package,
            content = files,
            kind = "third_party",
            rank = _PYPI_RANK,
            merge_affinity = _AFFINITY,
        )
    return runfiles_groups.entry(
        name = ctx.label,
        content = files,
        kind = "first_party",
        rank = _LIBRARY_RANK,
        merge_affinity = _AFFINITY,
    )

def _py_info_files(target, *, pyc_collection_enabled):
    """The transitive `PyInfo` file depsets a binary adds for a direct dep.

    This mirrors the loop in `_get_base_runfiles_for_binary` in
    py_executable.bzl.
    """
    if PyInfo in target:
        info = target[PyInfo]
    elif BuiltinPyInfo != None and BuiltinPyInfo in target:
        info = target[BuiltinPyInfo]
    else:
        return None
    transitive = [info.transitive_sources]
    if hasattr(info, "transitive_pyc_files"):
        transitive.append(info.transitive_pyc_files)
        if pyc_collection_enabled:
            transitive.append(info.transitive_implicit_pyc_files)
        else:
            transitive.append(info.transitive_implicit_pyc_source_files)
    return depset(transitive = transitive)

def collect_dep_entries(
        ctx,
        deps,
        *,
        pyc_collection_enabled,
        include_plain_dep_py_files = False):
    """Collects group entries from `deps`-like attributes.

    This deliberately doesn't use `runfiles_groups.collect()`: a dependency's
    contribution to a py_binary's runfiles isn't its `default_runfiles`
    alone, it's `default_runfiles` plus its `PyInfo` file depsets (selected
    by the pyc configuration), and only participating rules_python deps
    cover the latter in their entries.

    Args:
        ctx: The rule ctx.
        deps: list of Targets; the dependencies to collect entries from.
        pyc_collection_enabled: bool; whether a consuming binary will include
            implicit pyc files (True) or their source files (False).
        include_plain_dep_py_files: bool; whether `.py` files from
            non-`PyInfo` deps should be included in their fallback entry.
            `py_library` adds such files to its `PyInfo.transitive_sources`
            (see `create_py_info`), so they eventually reach a binary's
            runfiles; `py_binary` does not.

    Returns:
        struct with attributes:
        * direct: list of entries
        * transitive: list of entry depsets
    """
    direct = []
    transitive = []
    for dep in deps:
        if PyRunfilesGroupsInfo in dep:
            # A participating rules_python target: its entries cover both
            # its runfiles and its PyInfo contribution, by construction.
            transitive.append(dep[PyRunfilesGroupsInfo].entries)
            continue

        py_files = _py_info_files(
            dep,
            pyc_collection_enabled = pyc_collection_enabled,
        )

        if RunfilesGroupInfo in dep:
            # A public provider from another ruleset (or a py_binary used
            # as a dep): its entries cover the dep's default_runfiles, per
            # the provider contract. The PyInfo contribution isn't part of
            # that contract, so cover it with an extra per-target entry.
            # Usually the two mostly overlap (sources are also runfiles for
            # binaries); overlap is harmless, missing files are not.
            transitive.append(dep[RunfilesGroupInfo].entries)
            if py_files != None:
                direct.append(runfiles_groups.entry(
                    name = dep.label,
                    content = py_files,
                ))
            continue

        # No groups at all: cover the dep's entire contribution wholesale.
        default_info = dep[DefaultInfo]
        if py_files != None:
            content = ctx.runfiles(transitive_files = py_files).merge(
                default_info.default_runfiles,
            )
        elif include_plain_dep_py_files:
            # Mirrors create_py_info: `.py` files of non-PyInfo deps are
            # added to the library's transitive_sources. create_py_info
            # already flattens this same depset in the same analysis, so
            # the to_list() here is a cache hit, not a second flattening.
            content = ctx.runfiles(
                files = [
                    f
                    for f in default_info.files.to_list()
                    if f.extension == "py"
                ],
            ).merge(default_info.default_runfiles)
        else:
            content = default_info.default_runfiles
        direct.append(runfiles_groups.entry(name = dep.label, content = content))
    return struct(direct = direct, transitive = transitive)

def collect_py_info_only_entries(targets, *, pyc_collection_enabled):
    """Collects entries for targets contributing only via `PyInfo`.

    `pyi_deps` targets have their `PyInfo` merged into the depending
    target's `PyInfo` (so their transitive sources reach a consuming
    binary's runfiles), but their own runfiles are *not* collected. Their
    entries therefore consist of exactly their `PyInfo` file depsets; any
    group providers they carry are intentionally ignored, since those
    describe runfiles that don't reach the binary.

    Args:
        targets: list of Targets; e.g. the `pyi_deps` attribute values.
        pyc_collection_enabled: bool; see `collect_dep_entries`.

    Returns:
        struct with attributes:
        * direct: list of entries
        * transitive: list of entry depsets (always empty)
    """
    direct = []
    for target in targets:
        py_files = _py_info_files(
            target,
            pyc_collection_enabled = pyc_collection_enabled,
        )
        if py_files == None:
            continue
        direct.append(runfiles_groups.entry(
            name = target.label,
            content = py_files,
        ))
    return struct(direct = direct, transitive = [])

def collect_src_entries(srcs):
    """Collects entries for rule targets in `srcs`.

    `srcs` is normally plain source files, whose runfiles are empty. Rule
    targets in `srcs` (including the deprecated py_library-in-srcs pattern)
    have their `default_runfiles` collected by the implicit runfiles
    collection, so give each an entry with exactly that.

    Args:
        srcs: list of Targets; the `srcs` attribute values.

    Returns:
        struct with attributes:
        * direct: list of entries
        * transitive: list of entry depsets (always empty)
    """
    direct = []
    for target in srcs:
        runfiles = target[DefaultInfo].default_runfiles
        if runfiles.files or runfiles.symlinks or runfiles.root_symlinks:
            direct.append(runfiles_groups.entry(
                name = target.label,
                content = runfiles,
            ))
    return struct(direct = direct, transitive = [])

def collect_data_entries(data):
    """Collects group entries from the `data` attribute.

    This mirrors the implicit data-runfiles collection performed by
    `ctx.runfiles(collect_default = True)` (see `collect_runfiles` in
    common.bzl): plain file targets contribute the file itself, rule targets
    contribute their **data runfiles**.

    Plain files aren't given their own entries; they're returned in
    `own_files` for the caller to fold into the target's own group.
    Otherwise every data file of a PyPI package would end up as its own
    group.

    Note that {obj}`PyRunfilesGroupsInfo` is deliberately *not* read here:
    a py_library in `data` contributes only its data runfiles, not its
    sources (there is no `PyInfo` path through `data`), so its private
    entries would claim files the binary never gets.

    Known approximations (Starlark cannot exactly replicate the built-in
    collection logic):
    * A rule target whose data runfiles are empty but which provides
      exactly one default output is treated like a plain file target.
    * For targets providing `RunfilesGroupInfo` (e.g. a py_binary in
      `data`), the entries describe `default_runfiles` rather than
      `data_runfiles`. For rules_python executables the two are identical.

    Args:
        data: list of Targets; the `data` attribute values.

    Returns:
        struct with attributes:
        * direct: list of entries
        * transitive: list of entry depsets
        * own_files: list[File]; files from plain file targets, to be added
          to the collecting target's own group.
    """
    direct = []
    transitive = []
    own_files = []
    for target in data:
        if RunfilesGroupInfo in target:
            transitive.append(target[RunfilesGroupInfo].entries)
            continue
        runfiles = target[DefaultInfo].data_runfiles
        if not (runfiles.files or runfiles.symlinks or runfiles.root_symlinks):
            files = target[DefaultInfo].files
            if py_internal.is_singleton_depset(files):
                # A plain file target (source or output file): the implicit
                # collection adds the file itself.
                own_files.append(files.to_list()[0])

            # Otherwise: a rule target without data runfiles contributes
            # nothing. (This is the classic gotcha where a rule's default
            # outputs silently don't make it into runfiles.)
            continue
        direct.append(runfiles_groups.entry(name = target.label, content = runfiles))
    return struct(direct = direct, transitive = transitive, own_files = own_files)

def build_entries_depset(*collected):
    """Merges `collect_*_entries` results into one entry depset.

    Args:
        *collected: structs with `direct` (list of entries) and `transitive`
            (list of entry depsets) attributes.

    Returns:
        depset of entries with the order the protocol requires.
    """
    direct = []
    transitive = []
    for c in collected:
        direct.extend(c.direct)
        transitive.extend(c.transitive)
    return runfiles_groups.entries(direct = direct, transitive = transitive)

def create_runfiles_group_info(entries, *, executable_group = None):
    """Creates the public provider instance.

    Args:
        entries: depset of entries, from `build_entries_depset`.
        executable_group: Label | str | None; the group that should receive
            the executable and its supporting files.

    Returns:
        A RunfilesGroupInfo instance.
    """
    return RunfilesGroupInfo(
        entries = entries,
        executable_group = executable_group,
    )

def create_runtime_runfiles_group_info(runfiles):
    """The public provider for a py_runtime target: one runtime group.

    A runtime's default runfiles are trivially one group, so this satisfies
    the provider's union contract exactly.

    Args:
        runfiles: runfiles; the runtime target's default runfiles.

    Returns:
        A RunfilesGroupInfo instance.
    """
    return RunfilesGroupInfo(
        entries = runfiles_groups.entries(direct = [runtime_entry(runfiles)]),
        executable_group = None,
    )
