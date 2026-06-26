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
"""Implementation of PyInfo provider and PyInfo-specific utilities."""

load(":builders.bzl", "builders")
load(":reexports.bzl", "BuiltinPyInfo")

def _VenvSymlinkKind_typedef():
    """An enum of types of venv directories.

    :::{field} BIN
    :type: object

    Indicates to create paths under the directory that has binaries
    within the venv.
    :::

    :::{field} LIB
    :type: object

    Indicates to create paths under the venv's site-packages directory.
    :::

    :::{field} INCLUDE
    :type: object

    Indicates to create paths under the venv's include directory.
    :::

    :::{field} DATA
    :type: object

    Indicates to create paths under the venv's data directory.
    :::
    """

# buildifier: disable=name-conventions
VenvSymlinkKind = struct(
    TYPEDEF = _VenvSymlinkKind_typedef,
    BIN = "BIN",
    LIB = "LIB",
    INCLUDE = "INCLUDE",
    DATA = "DATA",
)

def _VenvSymlinkEntry_init(**kwargs):
    kwargs.setdefault("link_to_file", None)
    return kwargs

# A provider is used for memory efficiency.
# buildifier: disable=name-conventions
VenvSymlinkEntry, _ = provider(
    doc = """
An entry in `PyInfo.venv_symlinks`
""",
    init = _VenvSymlinkEntry_init,
    fields = {
        "files": """
:type: depset[File]

Files under `link_to_path`.

This is only used when multiple targets have overlapping `venv_path` paths. e.g.
if one adds files to `venv_path=a/` and another adds files to `venv_path=a/b/`.
""",
        "kind": """
:type: str

One of the {obj}`VenvSymlinkKind` values. It represents which directory within
the venv to create the path under.
""",
        "link_to_file": """
:type: File | None

A file that `venv_path` should point to. The file to link to should also be in
`files`.

:::{versionadded} 1.7.0
:::
""",
        "link_to_path": """
:type: str | None

A runfiles-root relative path that `venv_path` will symlink to (if
`link_to_file` is `None`). If `None`, it means to not create it in the venv.
""",
        "package": """
:type: str | None

Represents the PyPI package name that the code originates from. It is normalized according to the
PEP440 with all `-` replaced with `_`, i.e. the same as the package name in the hub repository that
it would come from.
""",
        "venv_path": """
:type: str

A path relative to the `kind` directory within the venv.
""",
        "version": """
:type: str | None

Represents the PyPI package version that the code originates from. It is normalized according to the
PEP440 standard.
""",
    },
)

def _VenvSymlinkEntryBuilder_typedef():
    """Builder for VenvSymlinkEntry.

    To create an instance, use {obj}`PyInfoBuilder.add_venv_symlink()`.

    :::{field} files
    :type: DepsetBuilder[File]
    :::

    :::{versionadded} VERSION_NEXT_FEATURE
    :::
    """

def _VenvSymlinkEntryBuilder():
    # buildifier: disable=uninitialized
    self = struct(
        _state = {
            "kind": None,
            "link_to_file": None,
            "link_to_path": None,
            "package": None,
            "venv_path": None,
            "version": None,
        },
        files = builders.DepsetBuilder(),
        get_kind = lambda: _VenvSymlinkEntryBuilder_get_kind(self),
        set_kind = lambda k: _VenvSymlinkEntryBuilder_set_kind(self, k),
        get_link_to_file = lambda: _VenvSymlinkEntryBuilder_get_link_to_file(self),
        set_link_to_file = lambda f: _VenvSymlinkEntryBuilder_set_link_to_file(self, f),
        get_link_to_path = lambda: _VenvSymlinkEntryBuilder_get_link_to_path(self),
        set_link_to_path = lambda p: _VenvSymlinkEntryBuilder_set_link_to_path(self, p),
        get_package = lambda: _VenvSymlinkEntryBuilder_get_package(self),
        set_package = lambda p: _VenvSymlinkEntryBuilder_set_package(self, p),
        get_venv_path = lambda: _VenvSymlinkEntryBuilder_get_venv_path(self),
        set_venv_path = lambda p: _VenvSymlinkEntryBuilder_set_venv_path(self, p),
        get_version = lambda: _VenvSymlinkEntryBuilder_get_version(self),
        set_version = lambda v: _VenvSymlinkEntryBuilder_set_version(self, v),
        build = lambda: _VenvSymlinkEntryBuilder_build(self),
    )
    return self

def _VenvSymlinkEntryBuilder_get_kind(self):
    """Get the kind of the symlink.

    Args:
        self: implicitly added.

    Returns:
        {type}`string` One of the {obj}`VenvSymlinkKind` values.
    """
    return self._state["kind"]

def _VenvSymlinkEntryBuilder_get_link_to_file(self):
    """Get the file that the symlink points to.

    Args:
        self: implicitly added.

    Returns:
        {type}`File | None`
    """
    return self._state["link_to_file"]

def _VenvSymlinkEntryBuilder_get_link_to_path(self):
    """Get the runfiles-root relative path that the symlink points to.

    Args:
        self: implicitly added.

    Returns:
        {type}`string | None`
    """
    return self._state["link_to_path"]

def _VenvSymlinkEntryBuilder_get_package(self):
    """Get the PyPI package name that the code originates from.

    Args:
        self: implicitly added.

    Returns:
        {type}`string | None`
    """
    return self._state["package"]

def _VenvSymlinkEntryBuilder_get_venv_path(self):
    """Get the path relative to the kind directory within the venv.

    Args:
        self: implicitly added.

    Returns:
        {type}`string`
    """
    return self._state["venv_path"]

def _VenvSymlinkEntryBuilder_get_version(self):
    """Get the PyPI package version that the code originates from.

    Args:
        self: implicitly added.

    Returns:
        {type}`string | None`
    """
    return self._state["version"]

def _VenvSymlinkEntryBuilder_set_kind(self, kind):
    """Set the kind of the symlink.

    Args:
        self: implicitly added.
        kind: {type}`string` One of the {obj}`VenvSymlinkKind` values.

    Returns:
        {type}`VenvSymlinkEntryBuilder` self.
    """
    _check_arg_type("kind", "string", kind)
    self._state["kind"] = kind
    return self

def _VenvSymlinkEntryBuilder_set_link_to_file(self, link_to_file):
    """Set the file that the symlink points to.

    Args:
        self: implicitly added.
        link_to_file: {type}`File | None`

    Returns:
        {type}`VenvSymlinkEntryBuilder` self.
    """
    if link_to_file != None:
        _check_arg_type("link_to_file", "File", link_to_file)
    self._state["link_to_file"] = link_to_file
    return self

def _VenvSymlinkEntryBuilder_set_link_to_path(self, link_to_path):
    """Set the runfiles-root relative path that the symlink points to.

    Args:
        self: implicitly added.
        link_to_path: {type}`string | None`

    Returns:
        {type}`VenvSymlinkEntryBuilder` self.
    """
    if link_to_path != None:
        _check_arg_type("link_to_path", "string", link_to_path)
    self._state["link_to_path"] = link_to_path
    return self

def _VenvSymlinkEntryBuilder_set_package(self, package):
    """Set the PyPI package name that the code originates from.

    Args:
        self: implicitly added.
        package: {type}`string | None`

    Returns:
        {type}`VenvSymlinkEntryBuilder` self.
    """
    if package != None:
        _check_arg_type("package", "string", package)
    self._state["package"] = package
    return self

def _VenvSymlinkEntryBuilder_set_venv_path(self, venv_path):
    """Set the path relative to the kind directory within the venv.

    Args:
        self: implicitly added.
        venv_path: {type}`string`

    Returns:
        {type}`VenvSymlinkEntryBuilder` self.
    """
    _check_arg_type("venv_path", "string", venv_path)
    self._state["venv_path"] = venv_path
    return self

def _VenvSymlinkEntryBuilder_set_version(self, version):
    """Set the PyPI package version that the code originates from.

    Args:
        self: implicitly added.
        version: {type}`string | None`

    Returns:
        {type}`VenvSymlinkEntryBuilder` self.
    """
    if version != None:
        _check_arg_type("version", "string", version)
    self._state["version"] = version
    return self

def _VenvSymlinkEntryBuilder_build(self):
    """Builds into a {obj}`VenvSymlinkEntry` object.

    Args:
        self: implicitly added.

    Returns:
        {type}`VenvSymlinkEntry`
    """
    if not self._state["venv_path"]:
        fail("venv_path must be set")
    return VenvSymlinkEntry(
        files = self.files.build(),
        kind = self._state["kind"],
        link_to_file = self._state["link_to_file"],
        link_to_path = self._state["link_to_path"],
        package = self._state["package"],
        venv_path = self._state["venv_path"],
        version = self._state["version"],
    )

# buildifier: disable=name-conventions
VenvSymlinkEntryBuilder = struct(
    TYPEDEF = _VenvSymlinkEntryBuilder_typedef,
    build = _VenvSymlinkEntryBuilder_build,
    get_kind = _VenvSymlinkEntryBuilder_get_kind,
    set_kind = _VenvSymlinkEntryBuilder_set_kind,
    get_link_to_file = _VenvSymlinkEntryBuilder_get_link_to_file,
    set_link_to_file = _VenvSymlinkEntryBuilder_set_link_to_file,
    get_link_to_path = _VenvSymlinkEntryBuilder_get_link_to_path,
    set_link_to_path = _VenvSymlinkEntryBuilder_set_link_to_path,
    get_package = _VenvSymlinkEntryBuilder_get_package,
    set_package = _VenvSymlinkEntryBuilder_set_package,
    get_venv_path = _VenvSymlinkEntryBuilder_get_venv_path,
    set_venv_path = _VenvSymlinkEntryBuilder_set_venv_path,
    get_version = _VenvSymlinkEntryBuilder_get_version,
    set_version = _VenvSymlinkEntryBuilder_set_version,
)

def _check_arg_type(name, required_type, value):
    """Check that a value is of an expected type."""
    value_type = type(value)
    if value_type != required_type:
        fail("parameter '{}' got value of type '{}', want '{}'".format(
            name,
            value_type,
            required_type,
        ))

def _PyInfo_init(
        *,
        transitive_sources,
        uses_shared_libraries = False,
        imports = depset(),
        has_py2_only_sources = False,
        has_py3_only_sources = False,
        direct_pyc_files = depset(),
        transitive_pyc_files = depset(),
        transitive_implicit_pyc_files = depset(),
        transitive_implicit_pyc_source_files = depset(),
        direct_original_sources = depset(),
        transitive_original_sources = depset(),
        direct_pyi_files = depset(),
        transitive_pyi_files = depset(),
        venv_symlinks = depset()):
    _check_arg_type("transitive_sources", "depset", transitive_sources)

    # Verify it's postorder compatible, but retain is original ordering.
    depset(transitive = [transitive_sources], order = "postorder")

    _check_arg_type("uses_shared_libraries", "bool", uses_shared_libraries)
    _check_arg_type("imports", "depset", imports)
    _check_arg_type("has_py2_only_sources", "bool", has_py2_only_sources)
    _check_arg_type("has_py3_only_sources", "bool", has_py3_only_sources)
    _check_arg_type("direct_pyc_files", "depset", direct_pyc_files)
    _check_arg_type("transitive_pyc_files", "depset", transitive_pyc_files)

    _check_arg_type("transitive_implicit_pyc_files", "depset", transitive_pyc_files)
    _check_arg_type("transitive_implicit_pyc_source_files", "depset", transitive_pyc_files)

    _check_arg_type("direct_original_sources", "depset", direct_original_sources)
    _check_arg_type("transitive_original_sources", "depset", transitive_original_sources)

    _check_arg_type("direct_pyi_files", "depset", direct_pyi_files)
    _check_arg_type("transitive_pyi_files", "depset", transitive_pyi_files)
    return {
        "direct_original_sources": direct_original_sources,
        "direct_pyc_files": direct_pyc_files,
        "direct_pyi_files": direct_pyi_files,
        "has_py2_only_sources": has_py2_only_sources,
        "has_py3_only_sources": has_py3_only_sources,
        "imports": imports,
        "transitive_implicit_pyc_files": transitive_implicit_pyc_files,
        "transitive_implicit_pyc_source_files": transitive_implicit_pyc_source_files,
        "transitive_original_sources": transitive_original_sources,
        "transitive_pyc_files": transitive_pyc_files,
        "transitive_pyi_files": transitive_pyi_files,
        "transitive_sources": transitive_sources,
        "uses_shared_libraries": uses_shared_libraries,
        "venv_symlinks": venv_symlinks,
    }

PyInfo, _unused_raw_py_info_ctor = provider(
    doc = """Encapsulates information provided by the Python rules.

Instead of creating this object directly, use {obj}`PyInfoBuilder` and
the {obj}`PyCommonApi` utilities.
""",
    init = _PyInfo_init,
    fields = {
        "direct_original_sources": """
:type: depset[File]

The `.py` source files (if any) that are considered directly provided by
the target. This field is intended so that static analysis tools can recover the
original Python source files, regardless of any build settings (e.g.
precompiling), so they can analyze source code. The values are typically the
`.py` files in the `srcs` attribute (or equivalent).

::::{versionadded} 1.1.0
::::
""",
        "direct_pyc_files": """
:type: depset[File]

Precompiled Python files that are considered directly provided
by the target and **must be included**.

These files usually come from, e.g., a library setting {attr}`precompile=enabled`
to forcibly enable precompiling for itself. Downstream binaries are expected
to always include these files, as the originating target expects them to exist.
""",
        "direct_pyi_files": """
:type: depset[File]

Type definition files (usually `.pyi` files) for the Python modules provided by
this target. Usually they describe the source files listed in
`direct_original_sources`. This field is primarily for static analysis tools.

These files are _usually_ build-time only and not included as part of a runnable
program.

:::{note}
This may contain implementation-specific file types specific to a particular
type checker.
:::

::::{versionadded} 1.1.0
::::
""",
        "has_py2_only_sources": """
:type: bool

Whether any of this target's transitive sources requires a Python 2 runtime.
""",
        "has_py3_only_sources": """
:type: bool

Whether any of this target's transitive sources requires a Python 3 runtime.
""",
        "imports": """\
:type: depset[str]

A depset of import path strings to be added to the `PYTHONPATH` of executable
Python targets. These are accumulated from the transitive `deps`.
The order of the depset is not guaranteed and may be changed in the future. It
is recommended to use `default` order (the default).
""",
        "transitive_implicit_pyc_files": """
:type: depset[File]

Automatically generated pyc files that downstream binaries (or equivalent)
can choose to include in their output. If not included, then
{obj}`transitive_implicit_pyc_source_files` should be included instead.

::::{versionadded} 0.37.0
::::
""",
        "transitive_implicit_pyc_source_files": """
:type: depset[File]

Source `.py` files for {obj}`transitive_implicit_pyc_files` that downstream
binaries (or equivalent) can choose to include in their output. If not included,
then {obj}`transitive_implicit_pyc_files` should be included instead.

::::{versionadded} 0.37.0
::::
""",
        "transitive_original_sources": """
:type: depset[File]

The transitive set of `.py` source files (if any) that are considered the
original sources for this target and its transitive dependencies. This field is
intended so that static analysis tools can recover the original Python source
files, regardless of any build settings (e.g. precompiling), so they can analyze
source code. The values are typically the `.py` files in the `srcs` attribute
(or equivalent).

This is superset of `direct_original_sources`.

::::{versionadded} 1.1.0
::::
""",
        "transitive_pyc_files": """
:type: depset[File]

The transitive set of precompiled files that must be included.

These files usually come from, e.g., a library setting {attr}`precompile=enabled`
to forcibly enable precompiling for itself. Downstream binaries are expected
to always include these files, as the originating target expects them to exist.
""",
        "transitive_pyi_files": """
:type: depset[File]

The transitive set of type definition files (usually `.pyi` files) for the
Python modules for this target and its transitive dependencies. this target.
Usually they describe the source files listed in `transitive_original_sources`.
This field is primarily for static analysis tools.

These files are _usually_ build-time only and not included as part of a runnable
program.

:::{note}
This may contain implementation-specific file types specific to a particular
type checker.
:::

::::{versionadded} 1.1.0
::::
""",
        "transitive_sources": """\
:type: depset[File]

A (`postorder`-compatible) depset of `.py` files that are considered required
and downstream binaries (or equivalent) **must** include in their outputs
to have a functioning program.

Normally, these are the `.py` files in the appearing in the target's `srcs` and
the `srcs` of the target's transitive `deps`, **however**, precompile settings
may cause `.py` files to be omitted. In particular, pyc-only builds may result
in this depset being **empty**.

::::{versionchanged} 0.37.0
The files are considered necessary for downstream binaries to function;
previously they were considerd informational and largely unused.
::::
""",
        "uses_shared_libraries": """
:type: bool

Whether any of this target's transitive `deps` has a shared library file (such
as a `.so` file).

This field is currently unused in Bazel and may go away in the future.
""",
        "venv_symlinks": """
:type: depset[VenvSymlinkEntry]

:::{include} /_includes/experimental_api.md
:::

:::{versionadded} 1.5.0
:::
""",
    },
)

# The "effective" PyInfo is what the canonical //python:py_info.bzl%PyInfo symbol refers to
_EffectivePyInfo = PyInfo

def _PyInfoBuilder_typedef():
    """Builder for PyInfo.

    To create an instance, use {obj}`py_common.get()` and call `PyInfoBuilder()`

    :::{field} direct_original_sources
    :type: DepsetBuilder[File]
    :::

    :::{field} direct_pyc_files
    :type: DepsetBuilder[File]
    :::

    :::{field} direct_pyi_files
    :type: DepsetBuilder[File]
    :::

    :::{field} imports
    :type: DepsetBuilder[str]
    :::

    :::{field} transitive_implicit_pyc_files
    :type: DepsetBuilder[File]
    :::

    :::{field} transitive_implicit_pyc_source_files
    :type: DepsetBuilder[File]
    :::

    :::{field} transitive_original_sources
    :type: DepsetBuilder[File]
    :::

    :::{field} transitive_pyc_files
    :type: DepsetBuilder[File]
    :::

    :::{field} transitive_pyi_files
    :type: DepsetBuilder[File]
    :::

    :::{field} transitive_sources
    :type: DepsetBuilder[File]
    :::

    :::{field} venv_symlinks
    :type: DepsetBuilder[tuple[str | None, str]]
    """

def _PyInfoBuilder_new():
    """Creates an instance.

    Returns:
        {type}`PyInfoBuilder`
    """

    # buildifier: disable=uninitialized
    self = struct(
        _has_py2_only_sources = [False],
        _has_py3_only_sources = [False],
        _uses_shared_libraries = [False],
        _venv_symlink_builders = [],
        add_venv_symlink = lambda *a, **k: _PyInfoBuilder_add_venv_symlink(self, *a, **k),
        build = lambda *a, **k: _PyInfoBuilder_build(self, *a, **k),
        build_builtin_py_info = lambda *a, **k: _PyInfoBuilder_build_builtin_py_info(self, *a, **k),
        direct_original_sources = builders.DepsetBuilder(),
        direct_pyc_files = builders.DepsetBuilder(),
        direct_pyi_files = builders.DepsetBuilder(),
        get_has_py2_only_sources = lambda *a, **k: _PyInfoBuilder_get_has_py2_only_sources(self, *a, **k),
        get_has_py3_only_sources = lambda *a, **k: _PyInfoBuilder_get_has_py3_only_sources(self, *a, **k),
        get_uses_shared_libraries = lambda *a, **k: _PyInfoBuilder_get_uses_shared_libraries(self, *a, **k),
        imports = builders.DepsetBuilder(),
        merge = lambda *a, **k: _PyInfoBuilder_merge(self, *a, **k),
        merge_all = lambda *a, **k: _PyInfoBuilder_merge_all(self, *a, **k),
        merge_has_py2_only_sources = lambda *a, **k: _PyInfoBuilder_merge_has_py2_only_sources(self, *a, **k),
        merge_has_py3_only_sources = lambda *a, **k: _PyInfoBuilder_merge_has_py3_only_sources(self, *a, **k),
        merge_target = lambda *a, **k: _PyInfoBuilder_merge_target(self, *a, **k),
        merge_targets = lambda *a, **k: _PyInfoBuilder_merge_targets(self, *a, **k),
        merge_uses_shared_libraries = lambda *a, **k: _PyInfoBuilder_merge_uses_shared_libraries(self, *a, **k),
        set_has_py2_only_sources = lambda *a, **k: _PyInfoBuilder_set_has_py2_only_sources(self, *a, **k),
        set_has_py3_only_sources = lambda *a, **k: _PyInfoBuilder_set_has_py3_only_sources(self, *a, **k),
        set_uses_shared_libraries = lambda *a, **k: _PyInfoBuilder_set_uses_shared_libraries(self, *a, **k),
        transitive_implicit_pyc_files = builders.DepsetBuilder(),
        transitive_implicit_pyc_source_files = builders.DepsetBuilder(),
        transitive_original_sources = builders.DepsetBuilder(),
        transitive_pyc_files = builders.DepsetBuilder(),
        transitive_pyi_files = builders.DepsetBuilder(),
        transitive_sources = builders.DepsetBuilder(),
        venv_symlinks = builders.DepsetBuilder(),
    )
    return self

def _PyInfoBuilder_add_venv_symlink(self):
    """Create and return a new VenvSymlinkEntryBuilder.

    :::{versionadded} VERSION_NEXT_FEATURE
    :::

    Args:
        self: implicitly added.

    Returns:
        {type}`VenvSymlinkEntryBuilder`
    """
    entry_builder = _VenvSymlinkEntryBuilder()
    self._venv_symlink_builders.append(entry_builder)
    return entry_builder

def _PyInfoBuilder_get_has_py3_only_sources(self):
    """Get the `has_py3_only_sources` value.

    Args:
        self: implicitly added.

    Returns:
        {type}`bool`
    """
    return self._has_py3_only_sources[0]

def _PyInfoBuilder_get_has_py2_only_sources(self):
    """Get the `has_py2_only_sources` value.

    Args:
        self: implicitly added.

    Returns:
        {type}`bool`
    """
    return self._has_py2_only_sources[0]

def _PyInfoBuilder_set_has_py2_only_sources(self, value):
    """Sets `has_py2_only_sources` to `value`.

    Args:
        self: implicitly added.
        value: {type}`bool` The value to set.

    Returns:
        {type}`PyInfoBuilder` self
    """
    self._has_py2_only_sources[0] = value
    return self

def _PyInfoBuilder_set_has_py3_only_sources(self, value):
    """Sets `has_py3_only_sources` to `value`.

    Args:
        self: implicitly added.
        value: {type}`bool` The value to set.

    Returns:
        {type}`PyInfoBuilder` self
    """
    self._has_py3_only_sources[0] = value
    return self

def _PyInfoBuilder_merge_has_py2_only_sources(self, value):
    """Sets `has_py2_only_sources` based on current and incoming `value`.

    Args:
        self: implicitly added.
        value: {type}`bool` Another `has_py2_only_sources` value. It will
            be merged into this builder's state.

    Returns:
        {type}`PyInfoBuilder` self
    """
    self._has_py2_only_sources[0] = self._has_py2_only_sources[0] or value
    return self

def _PyInfoBuilder_merge_has_py3_only_sources(self, value):
    """Sets `has_py3_only_sources` based on current and incoming `value`.

    Args:
        self: implicitly added.
        value: {type}`bool` Another `has_py3_only_sources` value. It will
            be merged into this builder's state.

    Returns:
        {type}`PyInfoBuilder` self
    """
    self._has_py3_only_sources[0] = self._has_py3_only_sources[0] or value
    return self

def _PyInfoBuilder_merge_uses_shared_libraries(self, value):
    """Sets `uses_shared_libraries` based on current and incoming `value`.

    Args:
        self: implicitly added.
        value: {type}`bool` Another `uses_shared_libraries` value. It will
            be merged into this builder's state.

    Returns:
        {type}`PyInfoBuilder` self
    """
    self._uses_shared_libraries[0] = self._uses_shared_libraries[0] or value
    return self

def _PyInfoBuilder_get_uses_shared_libraries(self):
    """Get the `uses_shared_libraries` value.

    Args:
        self: implicitly added.

    Returns:
        {type}`bool`
    """
    return self._uses_shared_libraries[0]

def _PyInfoBuilder_set_uses_shared_libraries(self, value):
    """Sets `uses_shared_libraries` to `value`.

    Args:
        self: implicitly added.
        value: {type}`bool` The value to set.

    Returns:
        {type}`PyInfoBuilder` self
    """
    self._uses_shared_libraries[0] = value
    return self

def _PyInfoBuilder_merge(self, *infos, direct = []):
    """Merge other PyInfos into this PyInfo.

    Args:
        self: implicitly added.
        *infos: {type}`PyInfo` objects to merge in, but only merge in their
            information into this object's transitive fields.
        direct: {type}`list[PyInfo]` objects to merge in, but also merge their
            direct fields into this object's direct fields.

    Returns:
        {type}`PyInfoBuilder` self
    """
    return self.merge_all(list(infos), direct = direct)

def _PyInfoBuilder_merge_all(self, transitive, *, direct = []):
    """Merge other PyInfos into this PyInfo.

    Args:
        self: implicitly added.
        transitive: {type}`list[PyInfo]` objects to merge in, but only merge in
            their information into this object's transitive fields.
        direct: {type}`list[PyInfo]` objects to merge in, but also merge their
            direct fields into this object's direct fields.

    Returns:
        {type}`PyInfoBuilder` self
    """
    for info in direct:
        # BuiltinPyInfo doesn't have this field
        if hasattr(info, "direct_pyc_files"):
            self.direct_original_sources.add(info.direct_original_sources)
            self.direct_pyc_files.add(info.direct_pyc_files)
            self.direct_pyi_files.add(info.direct_pyi_files)

    for info in direct + transitive:
        self.imports.add(info.imports)
        self.merge_has_py2_only_sources(info.has_py2_only_sources)
        self.merge_has_py3_only_sources(info.has_py3_only_sources)
        self.merge_uses_shared_libraries(info.uses_shared_libraries)
        self.transitive_sources.add(info.transitive_sources)

        # BuiltinPyInfo doesn't have these fields
        if hasattr(info, "transitive_pyc_files"):
            self.transitive_implicit_pyc_files.add(info.transitive_implicit_pyc_files)
            self.transitive_implicit_pyc_source_files.add(info.transitive_implicit_pyc_source_files)
            self.transitive_original_sources.add(info.transitive_original_sources)
            self.transitive_pyc_files.add(info.transitive_pyc_files)
            self.transitive_pyi_files.add(info.transitive_pyi_files)
            self.venv_symlinks.add(info.venv_symlinks)

    return self

def _PyInfoBuilder_merge_target(self, target):
    """Merge a target's Python information in this object.

    Args:
        self: implicitly added.
        target: {type}`Target` targets that provide PyInfo, or other relevant
            providers, will be merged into this object. If a target doesn't provide
            any relevant providers, it is ignored.

    Returns:
        {type}`PyInfoBuilder` self.
    """
    if PyInfo in target:
        self.merge(target[PyInfo])
    elif BuiltinPyInfo != None and BuiltinPyInfo in target:
        self.merge(target[BuiltinPyInfo])
    return self

def _PyInfoBuilder_merge_targets(self, targets):
    """Merge multiple targets into this object.

    Args:
        self: implicitly added.
        targets: {type}`list[Target]`
            targets that provide PyInfo, or other relevant
            providers, will be merged into this object. If a target doesn't provide
            any relevant providers, it is ignored.

    Returns:
        {type}`PyInfoBuilder` self.
    """
    for t in targets:
        self.merge_target(t)
    return self

def _PyInfoBuilder_build(self):
    """Builds into a {obj}`PyInfo` object.

    Args:
        self: implicitly added.

    Returns:
        {type}`PyInfo`
    """
    venv_symlinks = depset(
        direct = [b.build() for b in self._venv_symlink_builders],
        transitive = [self.venv_symlinks.build()],
    )

    return _EffectivePyInfo(
        has_py2_only_sources = self._has_py2_only_sources[0],
        has_py3_only_sources = self._has_py3_only_sources[0],
        imports = self.imports.build(),
        transitive_sources = self.transitive_sources.build(),
        uses_shared_libraries = self._uses_shared_libraries[0],
        direct_original_sources = self.direct_original_sources.build(),
        direct_pyc_files = self.direct_pyc_files.build(),
        direct_pyi_files = self.direct_pyi_files.build(),
        transitive_implicit_pyc_files = self.transitive_implicit_pyc_files.build(),
        transitive_implicit_pyc_source_files = self.transitive_implicit_pyc_source_files.build(),
        transitive_original_sources = self.transitive_original_sources.build(),
        transitive_pyc_files = self.transitive_pyc_files.build(),
        transitive_pyi_files = self.transitive_pyi_files.build(),
        venv_symlinks = venv_symlinks,
    )

def _PyInfoBuilder_build_builtin_py_info(self):
    """Builds into a Bazel-builtin PyInfo object, if available.

    Args:
        self: implicitly added.

    Returns:
        {type}`BuiltinPyInfo | None` None is returned if Bazel's
        builtin PyInfo object is disabled.
    """
    if BuiltinPyInfo == None:
        return None

    return BuiltinPyInfo(
        has_py2_only_sources = self._has_py2_only_sources[0],
        has_py3_only_sources = self._has_py3_only_sources[0],
        imports = self.imports.build(),
        transitive_sources = self.transitive_sources.build(),
        uses_shared_libraries = self._uses_shared_libraries[0],
    )

# Provided for documentation purposes
# buildifier: disable=name-conventions
PyInfoBuilder = struct(
    TYPEDEF = _PyInfoBuilder_typedef,
    new = _PyInfoBuilder_new,
    add_venv_symlink = _PyInfoBuilder_add_venv_symlink,
    build = _PyInfoBuilder_build,
    build_builtin_py_info = _PyInfoBuilder_build_builtin_py_info,
    get_has_py2_only_sources = _PyInfoBuilder_get_has_py2_only_sources,
    get_has_py3_only_sources = _PyInfoBuilder_get_has_py3_only_sources,
    get_uses_shared_libraries = _PyInfoBuilder_get_uses_shared_libraries,
    merge = _PyInfoBuilder_merge,
    merge_all = _PyInfoBuilder_merge_all,
    merge_has_py2_only_sources = _PyInfoBuilder_merge_has_py2_only_sources,
    merge_has_py3_only_sources = _PyInfoBuilder_merge_has_py3_only_sources,
    merge_target = _PyInfoBuilder_merge_target,
    merge_targets = _PyInfoBuilder_merge_targets,
    merge_uses_shared_libraries = _PyInfoBuilder_merge_uses_shared_libraries,
    set_has_py2_only_sources = _PyInfoBuilder_set_has_py2_only_sources,
    set_has_py3_only_sources = _PyInfoBuilder_set_has_py3_only_sources,
    set_uses_shared_libraries = _PyInfoBuilder_set_uses_shared_libraries,
)
