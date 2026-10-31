"""Runfiles group describers of the Python rules, for rules_runfiles_group.

Packaging rules built on rules_runfiles_group (e.g. rules_img's
`image_from_binary`) split a binary's runfiles into groups, typically one image
layer each. They walk the binary with an aspect and call the describer each
target lists in its `_aspect_rule_hints`, which says what runfiles the target
adds itself and which attributes the aspect merges groups in from.

A `py_binary` or `py_test` gets these groups:

* `rules_python#runtime`: the interpreter and standard library, described by the
  Python toolchain's `py_runtime_pair`. The aspect only walks toolchains on
  Bazel 8.8 or later.
* `rules_python#pypi/<distribution>`: one per PyPI distribution.
* One per `py_library`, and one per rule target in `data`, named by its label.
* The binary's own: its sources, bootstrap files and venv.

Only `//python/private:BUILD.bazel` loads this file, and the rules refer to the
describers by label: with Bazel 8's autoloads, loading rules_runfiles_group from
the files that define the rules is a load cycle.
"""

load("@rules_runfiles_group//runfiles_group:describe.bzl", "describe")
load(":attributes.bzl", "PycCollectionAttr")
load(":common.bzl", "is_py_source", "py_info_runfiles_files")
load(":flags.bzl", "PyiDepsToRunfilesFlag")
load(":py_executable.bzl", "get_runtime_files")
load(":py_executable_info.bzl", "PyExecutableInfo")
load(":py_info.bzl", "PyInfo")
load(":py_internal.bzl", "py_internal")
load(":py_library.bzl", "get_package_and_version")
load(":reexports.bzl", "BuiltinPyInfo")

# Stamped on every group, so Python groups stay together when a packager has to
# merge groups to fit a layer limit.
_MERGE_AFFINITY = "rules_python"

_RUNTIME_GROUP = "rules_python#runtime"

# Named by distribution rather than by label: whl_library's repository names are
# an implementation detail.
_PYPI_GROUP_PREFIX = "rules_python#pypi/"

# The toolchain type //python:toolchain_type is an alias of; the aspect matches
# toolchains by the actual label.
_RUNTIME_MERGE_FROM = describe.merge_from(
    toolchain = Label("@bazel_tools//tools/python:toolchain_type"),
)

def _pyc_collection_enabled(ctx, pyc_collection = PycCollectionAttr.INHERIT):
    """Whether a binary includes implicit pyc files instead of their sources.

    Args:
        ctx: {type}`ctx` the aspect ctx.
        pyc_collection: {type}`str` a binary's `pyc_collection` attribute; the
            default gives the configuration's choice.

    Returns:
        {type}`bool`
    """

    # PycCollectionAttr only reads these two attributes.
    return PycCollectionAttr.is_pyc_collection_enabled(struct(attr = struct(
        pyc_collection = pyc_collection,
        _precompile_flag = ctx.rule.attr._precompile_flag,
    )))

def _is_file(target):
    """Whether a target is a single file rather than a rule.

    Args:
        target: {type}`Target` an attribute's dependency.

    Returns:
        {type}`bool`
    """
    files = target[DefaultInfo].files
    if not py_internal.is_singleton_depset(files):
        return False
    file = files.to_list()[0]

    # A source file owns itself and a generated file is owned by the rule that
    # generates it, while a rule's own outputs are owned by the rule.
    return (file.owner == target.label) == file.is_source

def _is_empty(runfiles):
    """Whether a runfiles object holds nothing.

    Args:
        runfiles: {type}`runfiles`

    Returns:
        {type}`bool`
    """
    return not (runfiles.files or runfiles.symlinks or runfiles.root_symlinks)

def _has_py_info(target):
    """Whether a target provides PyInfo or the builtin PyInfo.

    Args:
        target: {type}`Target`

    Returns:
        {type}`bool`
    """
    return PyInfo in target or (BuiltinPyInfo != None and BuiltinPyInfo in target)

def _py_info_files(target, pyc_collection_enabled):
    """The files a binary takes from a target's PyInfo.

    Args:
        target: {type}`Target`
        pyc_collection_enabled: {type}`bool` whether the binary includes
            implicit pyc files instead of their sources.

    Returns:
        {type}`list[depset[File]]` empty for a target without PyInfo.
    """
    if PyInfo in target:
        return py_info_runfiles_files(target[PyInfo], pyc_collection_enabled)
    if BuiltinPyInfo != None and BuiltinPyInfo in target:
        return py_info_runfiles_files(target[BuiltinPyInfo], pyc_collection_enabled)
    return []

def _union(ctx, contents):
    """Combines group contents into one.

    Args:
        ctx: {type}`ctx` the aspect ctx.
        contents: {type}`list[depset[File] | runfiles]`

    Returns:
        {type}`depset[File] | runfiles` a depset if every content is one.
    """
    files = [c for c in contents if type(c) == "depset"]
    runfiles = [c for c in contents if type(c) != "depset"]
    if not runfiles:
        return depset(transitive = files)
    return ctx.runfiles(transitive_files = depset(transitive = files)).merge_all(runfiles)

def _kind(label):
    """The `kind` of the group of a target's own files.

    Args:
        label: {type}`Label` the target's label.

    Returns:
        {type}`str` `first_party` for the main repository, else `third_party`.
    """
    return "first_party" if label.repo_name == "" else "third_party"

def _pypi_entry(package, content, weight = None):
    """An entry in the group of a PyPI distribution.

    Args:
        package: {type}`str` the distribution name, as normalized by
            `get_package_and_version`.
        content: {type}`depset[File] | runfiles`
        weight: {type}`int | None` see `describe.entry`.

    Returns:
        {type}`RunfilesGroupInfo`
    """
    return describe.entry(
        name = _PYPI_GROUP_PREFIX + package,
        content = content,
        kind = "third_party",
        rank = describe.RANK_SHARED_DEPS,
        weight = weight,
        merge_affinity = _MERGE_AFFINITY,
    )

def _own_files(target, ctx, pyc_collection_enabled):
    """The files a target itself puts into a binary's runfiles.

    That is its sources (or their implicit pyc files), its other outputs, and
    the plain files in its `data`. Its dependencies' files are left to their own
    groups.

    Args:
        target: {type}`Target` a `py_library`, `py_binary` or `py_test`.
        ctx: {type}`ctx` the aspect ctx.
        pyc_collection_enabled: {type}`bool` whether the binary includes
            implicit pyc files instead of their sources.

    Returns:
        {type}`depset[File]`
    """
    info = target[PyInfo]

    # A Python target in srcs (whl_library's :pkg wraps its :srcs) describes its
    # own files.
    foreign = {
        f: None
        for dep in ctx.rule.attr.srcs
        if _has_py_info(dep)
        for f in dep[DefaultInfo].files.to_list()
    }

    # Sources that aren't .py files (directories, .pyc files) are outputs, but
    # never runfiles.
    sources = {f: None for f in info.direct_original_sources.to_list() if f not in foreign}
    direct = [
        f
        for f in target[DefaultInfo].files.to_list()
        if f not in foreign and (f not in sources or is_py_source(f))
    ]
    transitive = []
    if pyc_collection_enabled:
        transitive.append(info.direct_implicit_pyc_files)
    else:
        direct.extend([f for f in sources if is_py_source(f)])

    # A plain file listed in several targets' data lands in each of their groups.
    for dep in ctx.rule.attr.data:
        if _is_file(dep):
            direct.append(dep[DefaultInfo].files.to_list()[0])
    return depset(direct, transitive = transitive)

def _dep_fallback(ctx, dep, py_outputs):
    """The group of a dependency that doesn't describe its own groups.

    Args:
        ctx: {type}`ctx` the aspect ctx of the merging target.
        dep: {type}`Target` the dependency.
        py_outputs: {type}`bool` whether to include the dependency's .py outputs
            when it has no PyInfo.

    Returns:
        {type}`RunfilesGroupInfo | None` None if it contributes nothing.
    """
    content = _py_info_files(dep, _pyc_collection_enabled(ctx))
    if py_outputs and not content:
        content.append(depset([f for f in dep[DefaultInfo].files.to_list() if is_py_source(f)]))
    runfiles = dep[DefaultInfo].default_runfiles
    if not _is_empty(runfiles):
        content.append(runfiles)
    if not content:
        return None
    return describe.entry(name = dep.label, content = _union(ctx, content))

def _library_dep_fallback(ctx, dep):
    """`_dep_fallback` for a `py_library`'s `deps`.

    A `py_library` adds the .py outputs of a dependency without PyInfo to its own
    PyInfo, so the dependency's group holds them.

    Args:
        ctx: {type}`ctx` the aspect ctx of the library.
        dep: {type}`Target` the dependency.

    Returns:
        {type}`RunfilesGroupInfo | None`
    """
    return _dep_fallback(ctx, dep, py_outputs = True)

def _executable_dep_fallback(ctx, dep):
    """`_dep_fallback` for a binary's `deps`.

    Args:
        ctx: {type}`ctx` the aspect ctx of the binary.
        dep: {type}`Target` the dependency.

    Returns:
        {type}`RunfilesGroupInfo | None`
    """
    return _dep_fallback(ctx, dep, py_outputs = False)

def _data_fallback(ctx, dep):
    """The group of a rule target in `data` that doesn't describe its own groups.

    Args:
        ctx: {type}`ctx` the aspect ctx of the merging target.
        dep: {type}`Target` the dependency.

    Returns:
        {type}`RunfilesGroupInfo | None` None for a plain file, which is in the
        merging target's own group, or a target that contributes nothing.
    """
    default_info = dep[DefaultInfo]
    if _is_file(dep) or (not default_info.files and _is_empty(default_info.data_runfiles)):
        return None
    content = _union(ctx, [default_info.files, default_info.data_runfiles])
    return describe.entry(name = dep.label, content = content)

def _srcs_fallback(ctx, dep):
    """The group of a rule target in `srcs` that doesn't describe its own groups.

    Args:
        ctx: {type}`ctx` the aspect ctx of the merging target.
        dep: {type}`Target` the dependency.

    Returns:
        {type}`RunfilesGroupInfo | None` None for a plain file, which is in the
        merging target's own group.
    """
    if _is_file(dep):
        return None
    return _dep_fallback(ctx, dep, py_outputs = False)

def _describe_py_library(target, ctx):
    """Describes a `py_library`: one group for its own files.

    The group is named after the distribution for a library with a
    `.dist-info/METADATA` file in `data` (i.e. one from a wheel), and takes
    everything in its `data` too. Otherwise it's named by the library's label.
    Its weight is the number of files in `srcs` and `data`.

    Args:
        target: {type}`Target` the library.
        ctx: {type}`ctx` the aspect ctx.

    Returns:
        {type}`struct` from `describe.node`.
    """
    pyc_collection_enabled = _pyc_collection_enabled(ctx)
    content = _own_files(target, ctx, pyc_collection_enabled)

    # With pyi_deps_to_runfiles, a binary takes the files of pyi_deps from this
    # target's PyInfo, but not their runfiles.
    if PyiDepsToRunfilesFlag.is_enabled(struct(attr = ctx.rule.attr, var = ctx.var)):
        content = depset(transitive = [content] + [
            files
            for dep in ctx.rule.attr.pyi_deps
            for files in _py_info_files(dep, pyc_collection_enabled)
        ])

    weight = len(ctx.rule.files.srcs) + len(ctx.rule.files.data)
    data = describe.merge_from("data", fallback = _data_fallback)
    package, _ = get_package_and_version(ctx.rule.files.data)
    if package:
        entry = _pypi_entry(package, content, weight)

        # whl_library lists a console script in `data` both on its own and in a
        # filegroup, which would put it in two groups.
        data = describe.merge_from("data", fallback = _data_fallback, into = entry.name)
    else:
        kind = _kind(ctx.label)
        entry = describe.entry(
            name = ctx.label,
            content = content,
            kind = kind,
            rank = describe.RANK_SHARED_DEPS if kind == "third_party" else describe.RANK_EXECUTABLE,
            weight = weight,
            merge_affinity = _MERGE_AFFINITY,
        )
    return describe.node(
        add = [entry] if content else [],
        merge_from = [
            data,
            describe.merge_from("deps", fallback = _library_dep_fallback),
            describe.merge_from("srcs", fallback = _srcs_fallback),
        ],
    )

py_library_runfiles_group_describer = describe.make_describer_rule(
    describe = _describe_py_library,
)

def _venv_entries(ctx, venv_runfiles):
    """Moves the venv's links to PyPI distribution files into their groups.

    A packager that stores symlinks as copies of their targets can then keep each
    link next to the file it points to, instead of copying the file (typically a
    shared library) into the binary's group.

    Args:
        ctx: {type}`ctx` the aspect ctx of the binary.
        venv_runfiles: {type}`runfiles` the binary's `PyExecutableInfo.venv_runfiles`.

    Returns:
        {type}`tuple[list[RunfilesGroupInfo], runfiles]` the entries for the
        distributions' groups, and the venv runfiles left for the binary's.
    """

    # Keyed by every file an entry covers, not just the one it links to: where
    # distributions share a directory (namespace packages), the venv links each
    # file in it instead.
    packages = {
        file: entry.package
        for entry in depset(transitive = [
            dep[PyInfo].venv_symlinks
            for dep in ctx.rule.attr.deps
            if PyInfo in dep
        ]).to_list()
        if entry.package
        for file in entry.files.to_list()
    }
    by_package = {}
    own_links = {}
    for link in venv_runfiles.root_symlinks.to_list():
        package = packages.get(link.target_file)
        links = by_package.setdefault(package, {}) if package else own_links
        links[link.path] = link.target_file
    entries = [
        _pypi_entry(package, ctx.runfiles(root_symlinks = links))
        for package, links in by_package.items()
    ]
    return entries, ctx.runfiles(transitive_files = venv_runfiles.files, root_symlinks = own_links)

def _describe_py_executable(target, ctx):
    """Describes a `py_binary` or `py_test`.

    Its group holds its own files, bootstrap files and venv, and is the group
    the packager puts the executable in. The runtime and the dependencies'
    groups are merged in.

    Args:
        target: {type}`Target` the binary.
        ctx: {type}`ctx` the aspect ctx.

    Returns:
        {type}`struct` from `describe.node`.
    """
    info = target[PyExecutableInfo]
    pyc_collection_enabled = _pyc_collection_enabled(ctx, ctx.rule.attr.pyc_collection)
    content = [
        _own_files(target, ctx, pyc_collection_enabled),
        depset([f for f in (info.build_data_file, info.stage2_bootstrap) if f]),
    ]
    venv_runfiles = info.venv_runfiles
    add = []

    # Two cases where the binary's group takes its dependencies:
    # * The legacy __init__.py files: they're generated for every directory in
    #   the runfiles, the runtime's included. Checking for them is cheap unless
    #   they exist.
    # * A pyc selection that differs from the configuration's, which is the one
    #   dependencies describe their files with.
    if info.app_runfiles.empty_filenames:
        content.append(info.runfiles_without_exe)
        merge_from = []
    elif pyc_collection_enabled != _pyc_collection_enabled(ctx):
        content.append(info.app_runfiles)
        merge_from = [_RUNTIME_MERGE_FROM]
    else:
        if venv_runfiles:
            add, venv_runfiles = _venv_entries(ctx, venv_runfiles)
        merge_from = [
            _RUNTIME_MERGE_FROM,
            describe.merge_from("_debugger_flag", fallback = _executable_dep_fallback),
            describe.merge_from("data", fallback = _data_fallback),
            describe.merge_from("deps", fallback = _executable_dep_fallback),
            describe.merge_from("srcs", fallback = _srcs_fallback),
        ]
    content.extend([rf for rf in (venv_runfiles, info.venv_interpreter_runfiles) if rf])

    return describe.node(
        add = [describe.entry(
            name = ctx.label,
            content = _union(ctx, content),
            kind = _kind(ctx.label),
            merge_affinity = _MERGE_AFFINITY,
        )] + add,
        merge_from = merge_from,
        executable_group = ctx.label,
    )

py_executable_runfiles_group_describer = describe.make_describer_rule(
    describe = _describe_py_executable,
)

def _describe_py_runtime_pair(target, ctx):
    """Describes a Python toolchain: one group for its runtime's files.

    Every binary using the toolchain merges in the same group, so a packager
    builds it once.

    Args:
        target: {type}`Target` the `py_runtime_pair`.
        ctx: {type}`ctx` the aspect ctx.

    Returns:
        {type}`struct` from `describe.node`.
    """
    runtime = target[platform_common.ToolchainInfo].py3_runtime
    files = get_runtime_files(ctx, runtime) if runtime else depset()
    return describe.node(add = [describe.entry(
        name = _RUNTIME_GROUP,
        content = files,
        kind = "foundation",
        rank = describe.RANK_FOUNDATION,
        do_not_merge = True,
        merge_affinity = _MERGE_AFFINITY,
    )] if files else [])

py_runtime_pair_runfiles_group_describer = describe.make_describer_rule(
    describe = _describe_py_runtime_pair,
)
