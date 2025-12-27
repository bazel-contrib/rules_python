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
"""Various things common to rule implementations."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":cc_helper.bzl", "cc_helper")
load(":py_cc_link_params_info.bzl", "PyCcLinkParamsInfo")
load(":py_info.bzl", "PyInfo", "PyInfoBuilder")
load(":py_internal.bzl", "py_internal")
load(":reexports.bzl", "BuiltinPyInfo")

_testing = testing
_platform_common = platform_common
_coverage_common = coverage_common
PackageSpecificationInfo = getattr(py_internal, "PackageSpecificationInfo", None)

# Extensions without the dot
_PYTHON_SOURCE_EXTENSIONS = ["py"]

# Extensions that mean a file is relevant to Python
PYTHON_FILE_EXTENSIONS = [
    "dll",  # Python C modules, Windows specific
    "dylib",  # Python C modules, Mac specific
    "py",
    "pyc",
    "pth",  # import 'pth' files
    "pyi",
    "so",  # Python C modules, usually Linux
]

def create_binary_semantics_struct(
        *,
        get_central_uncachable_version_file,
        get_native_deps_dso_name,
        should_build_native_deps_dso,
        should_include_build_data):
    """Helper to ensure a semantics struct has all necessary fields.

    Call this instead of a raw call to `struct(...)`; it'll help ensure all
    the necessary functions are being correctly provided.

    Args:
        get_central_uncachable_version_file: Callable that returns an optional
            Artifact; this artifact is special: it is never cached and is a copy
            of `ctx.version_file`; see py_builtins.copy_without_caching
        get_native_deps_dso_name: Callable that returns a string, which is the
            basename (with extension) of the native deps DSO library.
        should_build_native_deps_dso: Callable that returns bool; True if
            building a native deps DSO is supported, False if not.
        should_include_build_data: Callable that returns bool; True if
            build data should be generated, False if not.
    Returns:
        A "BinarySemantics" struct.
    """
    return struct(
        # keep-sorted
        get_central_uncachable_version_file = get_central_uncachable_version_file,
        get_native_deps_dso_name = get_native_deps_dso_name,
        should_build_native_deps_dso = should_build_native_deps_dso,
        should_include_build_data = should_include_build_data,
    )

def create_cc_details_struct(
        *,
        cc_info_for_propagating,
        cc_info_for_self_link,
        cc_info_with_extra_link_time_libraries,
        extra_runfiles,
        cc_toolchain,
        feature_config,
        **kwargs):
    """Creates a CcDetails struct.

    Args:
        cc_info_for_propagating: CcInfo that is propagated out of the target
            by returning it within a PyCcLinkParamsProvider object.
        cc_info_for_self_link: CcInfo that is used when linking for the
            binary (or its native deps DSO) itself. This may include extra
            information that isn't propagating (e.g. a custom malloc)
        cc_info_with_extra_link_time_libraries: CcInfo of extra link time
            libraries that MUST come after `cc_info_for_self_link` (or possibly
            always last; not entirely clear) when passed to
            `link.linking_contexts`.
        extra_runfiles: runfiles of extra files needed at runtime, usually as
            part of `cc_info_with_extra_link_time_libraries`; should be added to
            runfiles.
        cc_toolchain: CcToolchain that should be used when building.
        feature_config: struct from cc_configure_features(); see
            //python/private:py_executable.bzl%cc_configure_features.
        **kwargs: Additional keys/values to set in the returned struct. This is to
            facilitate extensions with less patching. Any added fields should
            pick names that are unlikely to collide if the CcDetails API has
            additional fields added.

    Returns:
        A `CcDetails` struct.
    """
    return struct(
        cc_info_for_propagating = cc_info_for_propagating,
        cc_info_for_self_link = cc_info_for_self_link,
        cc_info_with_extra_link_time_libraries = cc_info_with_extra_link_time_libraries,
        extra_runfiles = extra_runfiles,
        cc_toolchain = cc_toolchain,
        feature_config = feature_config,
        **kwargs
    )

def create_executable_result_struct(*, extra_files_to_build, output_groups, extra_runfiles = None):
    """Creates a `CreateExecutableResult` struct.

    This is the return value type of the semantics create_executable function.

    Args:
        extra_files_to_build: depset of File; additional files that should be
            included as default outputs.
        output_groups: dict[str, depset[File]]; additional output groups that
            should be returned.
        extra_runfiles: A runfiles object of additional runfiles to include.

    Returns:
        A `CreateExecutableResult` struct.
    """
    return struct(
        extra_files_to_build = extra_files_to_build,
        output_groups = output_groups,
        extra_runfiles = extra_runfiles,
    )

def csv(values):
    """Convert a list of strings to comma separated value string."""
    return ", ".join(sorted(values))

def filter_to_py_srcs(srcs):
    """Filters .py files from the given list of files"""

    # TODO(b/203567235): Get the set of recognized extensions from
    # elsewhere, as there may be others. e.g. Bazel recognizes .py3
    # as a valid extension.
    return [f for f in srcs if f.extension == "py"]

def collect_cc_info(ctx, extra_deps = []):
    """Collect C++ information from dependencies for Bazel.

    Args:
        ctx: Rule ctx; must have `deps` attribute.
        extra_deps: list of Target to also collect C+ information from.

    Returns:
        CcInfo provider of merged information.
    """
    cc_infos = []
    for dep in collect_deps(ctx, extra_deps):
        if CcInfo in dep:
            cc_infos.append(dep[CcInfo])

        if PyCcLinkParamsInfo in dep:
            cc_infos.append(dep[PyCcLinkParamsInfo].cc_info)

    return cc_common.merge_cc_infos(cc_infos = cc_infos)

def collect_imports(ctx, extra_deps = []):
    """Collect the direct and transitive `imports` strings.

    Args:
        ctx: {type}`ctx` the current target ctx
        extra_deps: list of Target to also collect imports from.

    Returns:
        {type}`depset[str]` of import paths
    """

    transitive = []
    for dep in collect_deps(ctx, extra_deps):
        if PyInfo in dep:
            transitive.append(dep[PyInfo].imports)
        if BuiltinPyInfo != None and BuiltinPyInfo in dep:
            transitive.append(dep[BuiltinPyInfo].imports)
    return depset(direct = get_imports(ctx), transitive = transitive)

def get_imports(ctx):
    """Gets the imports from a rule's `imports` attribute.

    Args:
        ctx: Rule ctx.

    Returns:
        List of strings.
    """
    prefix = "{}/{}".format(
        ctx.workspace_name,
        py_internal.get_label_repo_runfiles_path(ctx.label),
    )
    result = []
    for import_str in ctx.attr.imports:
        import_str = ctx.expand_make_variables("imports", import_str, {})
        if import_str.startswith("/"):
            continue

        # To prevent "escaping" out of the runfiles tree, we normalize
        # the path and ensure it doesn't have up-level references.
        import_path = paths.normalize("{}/{}".format(prefix, import_str))
        if import_path.startswith("../") or import_path == "..":
            fail("Path '{}' references a path above the execution root".format(
                import_str,
            ))
        result.append(import_path)
    return result

def collect_runfiles(ctx, files = depset()):
    """Collects the necessary files from the rule's context.

    This presumes the ctx is for a py_binary, py_test, or py_library rule.

    Args:
        ctx: rule ctx
        files: depset of extra files to include in the runfiles.
    Returns:
        runfiles necessary for the ctx's target.
    """
    return ctx.runfiles(
        transitive_files = files,
        # This little arg carries a lot of weight, but because Starlark doesn't
        # have a way to identify if a target is just a File, the equivalent
        # logic can't be re-implemented in pure-Starlark.
        #
        # Under the hood, it calls the Java `Runfiles#addRunfiles(ctx,
        # DEFAULT_RUNFILES)` method, which is the what the Java implementation
        # of the Python rules originally did, and the details of how that method
        # works have become relied on in various ways. Specifically, what it
        # does is visit the srcs, deps, and data attributes in the following
        # ways:
        #
        # For each target in the "data" attribute...
        #   If the target is a File, then add that file to the runfiles.
        #   Otherwise, add the target's **data runfiles** to the runfiles.
        #
        # Note that, contrary to best practice, the default outputs of the
        # targets in `data` are *not* added, nor are the default runfiles.
        #
        # This ends up being important for several reasons, some of which are
        # specific to Google-internal features of the rules.
        #   * For Python executables, we have to use `data_runfiles` to avoid
        #     conflicts for the build data files. Such files have
        #     target-specific content, but uses a fixed location, so if a
        #     binary has another binary in `data`, and both try to specify a
        #     file for that file path, then a warning is printed and an
        #     arbitrary one will be used.
        #   * For rules with _entirely_ different sets of files in data runfiles
        #     vs default runfiles vs default outputs. For example,
        #     proto_library: documented behavior of this rule is that putting it
        #     in the `data` attribute will cause the transitive closure of
        #     `.proto` source files to be included. This set of sources is only
        #     in the `data_runfiles` (`default_runfiles` is empty).
        #   * For rules with a _subset_ of files in data runfiles. For example,
        #     a certain Google rule used for packaging arbitrary binaries will
        #     generate multiple versions of a binary (e.g. different archs,
        #     stripped vs un-stripped, etc) in its default outputs, but only
        #     one of them in the runfiles; this helps avoid large, unused
        #     binaries contributing to remote executor input limits.
        #
        # Unfortunately, the above behavior also results in surprising behavior
        # in some cases. For example, simple custom rules that only return their
        # files in their default outputs won't have their files included. Such
        # cases must either return their files in runfiles, or use `filegroup()`
        # which will do so for them.
        #
        # For each target in "srcs" and "deps"...
        #   Add the default runfiles of the target to the runfiles. While this
        #   is desirable behavior, it also ends up letting a `py_library`
        #   be put in `srcs` and still mostly work.
        # TODO(b/224640180): Reject py_library et al rules in srcs.
        collect_default = True,
    )

def create_py_info(
        ctx,
        *,
        original_sources,
        required_py_files,
        required_pyc_files,
        implicit_pyc_files,
        implicit_pyc_source_files,
        imports,
        venv_symlinks = []):
    """Create PyInfo provider.

    Args:
        ctx: rule ctx.
        original_sources: `depset[File]`; the original input sources from `srcs`
        required_py_files: `depset[File]`; the direct, `.py` sources for the
            target that **must** be included by downstream targets. This should
            only be Python source files. It should not include pyc files.
        required_pyc_files: `depset[File]`; the direct `.pyc` files this target
            produces.
        implicit_pyc_files: `depset[File]` pyc files that are only used if pyc
            collection is enabled.
        implicit_pyc_source_files: `depset[File]` source files for implicit pyc
            files that are used when the implicit pyc files are not.
        implicit_pyc_files: {type}`depset[File]` Implicitly generated pyc files
            that a binary can choose to include.
        imports: depset of strings; the import path values to propagate.
        venv_symlinks: {type}`list[VenvSymlinkEntry]` instances for
            symlinks to create in the consuming binary's venv.

    Returns:
        A tuple of the PyInfo instance and a depset of the
        transitive sources collected from dependencies (the latter is only
        necessary for deprecated extra actions support).
    """
    py_info = PyInfoBuilder.new()
    py_info.venv_symlinks.add(venv_symlinks)
    py_info.direct_original_sources.add(original_sources)
    py_info.direct_pyc_files.add(required_pyc_files)
    py_info.direct_pyi_files.add(ctx.files.pyi_srcs)
    py_info.transitive_original_sources.add(original_sources)
    py_info.transitive_pyc_files.add(required_pyc_files)
    py_info.transitive_pyi_files.add(ctx.files.pyi_srcs)
    py_info.transitive_implicit_pyc_files.add(implicit_pyc_files)
    py_info.transitive_implicit_pyc_source_files.add(implicit_pyc_source_files)
    py_info.imports.add(imports)
    py_info.merge_has_py2_only_sources(ctx.attr.srcs_version in ("PY2", "PY2ONLY"))
    py_info.merge_has_py3_only_sources(ctx.attr.srcs_version in ("PY3", "PY3ONLY"))

    for target in ctx.attr.deps:
        # PyInfo may not be present e.g. cc_library rules.
        if PyInfo in target or (BuiltinPyInfo != None and BuiltinPyInfo in target):
            py_info.merge(_get_py_info(target))
        else:
            # TODO(b/228692666): Remove this once non-PyInfo targets are no
            # longer supported in `deps`.
            files = target[DefaultInfo].files.to_list()
            for f in files:
                if f.extension == "py":
                    py_info.transitive_sources.add(f)
                py_info.merge_uses_shared_libraries(cc_helper.is_valid_shared_library_artifact(f))
    for target in ctx.attr.pyi_deps:
        # PyInfo may not be present e.g. cc_library rules.
        if PyInfo in target or (BuiltinPyInfo != None and BuiltinPyInfo in target):
            py_info.merge(_get_py_info(target))

    py_info.transitive_sources.add(required_py_files)

    # We only look at data to calculate uses_shared_libraries, if it's already
    # true, then we don't need to waste time looping over it.
    if not py_info.get_uses_shared_libraries():
        # Similar to the above, except we only calculate uses_shared_libraries
        for target in ctx.attr.data:
            # TODO(b/234730058): Remove checking for PyInfo in data once depot
            # cleaned up.
            if PyInfo in target or (BuiltinPyInfo != None and BuiltinPyInfo in target):
                info = _get_py_info(target)
                py_info.merge_uses_shared_libraries(info.uses_shared_libraries)
            else:
                files = target[DefaultInfo].files.to_list()
                for f in files:
                    py_info.merge_uses_shared_libraries(cc_helper.is_valid_shared_library_artifact(f))
                    if py_info.get_uses_shared_libraries():
                        break
            if py_info.get_uses_shared_libraries():
                break

    return py_info.build(), py_info.build_builtin_py_info()

def _get_py_info(target):
    return target[PyInfo] if PyInfo in target or BuiltinPyInfo == None else target[BuiltinPyInfo]

def create_instrumented_files_info(ctx):
    return _coverage_common.instrumented_files_info(
        ctx,
        source_attributes = ["srcs"],
        dependency_attributes = ["deps", "data"],
        extensions = _PYTHON_SOURCE_EXTENSIONS,
    )

def create_output_group_info(transitive_sources, extra_groups):
    return OutputGroupInfo(
        compilation_prerequisites_INTERNAL_ = transitive_sources,
        compilation_outputs = transitive_sources,
        **extra_groups
    )

def maybe_add_test_execution_info(providers, ctx):
    """Adds ExecutionInfo, if necessary for proper test execution.

    Args:
        providers: Mutable list of providers; may have ExecutionInfo
            provider appended.
        ctx: Rule ctx.
    """

    # When built for Apple platforms, require the execution to be on a Mac.
    # TODO(b/176993122): Remove when bazel automatically knows to run on darwin.
    if target_platform_has_any_constraint(ctx, ctx.attr._apple_constraints):
        providers.append(_testing.ExecutionInfo({"requires-darwin": ""}))

_BOOL_TYPE = type(True)

def is_bool(v):
    return type(v) == _BOOL_TYPE

def is_file(v):
    return type(v) == "File"

def target_platform_has_any_constraint(ctx, constraints):
    """Check if target platform has any of a list of constraints.

    Args:
      ctx: rule context.
      constraints: label_list of constraints.

    Returns:
      True if target platform has at least one of the constraints.
    """
    for constraint in constraints:
        constraint_value = constraint[_platform_common.ConstraintValueInfo]
        if ctx.target_platform_has_constraint(constraint_value):
            return True
    return False

def relative_path(from_, to):
    """Compute a relative path from one path to another.

    Args:
        from_: {type}`str` the starting directory. Note that it should be
            a directory because relative-symlinks are relative to the
            directory the symlink resides in.
        to: {type}`str` the path that `from_` wants to point to

    Returns:
        {type}`str` a relative path
    """
    from_parts = from_.split("/")
    to_parts = to.split("/")

    # Strip common leading parts from both paths
    n = min(len(from_parts), len(to_parts))
    for _ in range(n):
        if from_parts[0] == to_parts[0]:
            from_parts.pop(0)
            to_parts.pop(0)
        else:
            break

    # Impossible to compute a relative path without knowing what ".." is
    if from_parts and from_parts[0] == "..":
        fail("cannot compute relative path from '%s' to '%s'", from_, to)

    parts = ([".."] * len(from_parts)) + to_parts
    return paths.join(*parts)

def runfiles_root_path(ctx, short_path):
    """Compute a runfiles-root relative path from `File.short_path`

    Args:
        ctx: current target ctx
        short_path: str, a main-repo relative path from `File.short_path`

    Returns:
        {type}`str`, a runflies-root relative path
    """

    # The ../ comes from short_path is for files in other repos.
    if short_path.startswith("../"):
        return short_path[3:]
    else:
        return "{}/{}".format(ctx.workspace_name, short_path)

def collect_deps(ctx, extra_deps = []):
    """Collect the dependencies from the rule's context.

    Args:
        ctx: rule ctx
        extra_deps: list of Target to also collect dependencies from.

    Returns:
        list of Target
    """
    deps = ctx.attr.deps
    if extra_deps:
        deps = list(deps)
        deps.extend(extra_deps)
    return deps
