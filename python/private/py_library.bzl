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
"""Common code for implementing py_library rules."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":attr_builders.bzl", "attrb")
load(
    ":attributes.bzl",
    "COMMON_ATTRS",
    "IMPORTS_ATTRS",
    "PY_SRCS_ATTRS",
    "PrecompileAttr",
    "REQUIRED_EXEC_GROUP_BUILDERS",
)
load(":builders.bzl", "builders")
load(
    ":common.bzl",
    "PYTHON_FILE_EXTENSIONS",
    "collect_cc_info",
    "collect_imports",
    "collect_runfiles",
    "create_instrumented_files_info",
    "create_library_semantics_struct",
    "create_output_group_info",
    "create_py_info",
    "filter_to_py_srcs",
    "get_imports",
    "runfiles_root_path",
)
load(":flags.bzl", "AddSrcsToRunfilesFlag", "PrecompileFlag", "VenvsSitePackages")
load(":precompile.bzl", "maybe_precompile")
load(":py_cc_link_params_info.bzl", "PyCcLinkParamsInfo")
load(":py_internal.bzl", "py_internal")
load(":rule_builders.bzl", "ruleb")
load(
    ":toolchain_types.bzl",
    "EXEC_TOOLS_TOOLCHAIN_TYPE",
    TOOLCHAIN_TYPE = "TARGET_TOOLCHAIN_TYPE",
)

_py_builtins = py_internal

LIBRARY_ATTRS = dicts.add(
    COMMON_ATTRS,
    PY_SRCS_ATTRS,
    IMPORTS_ATTRS,
    {
        "experimental_venvs_site_packages": lambda: attrb.Label(
            doc = """
**INTERNAL ATTRIBUTE. SHOULD ONLY BE SET BY rules_python-INTERNAL CODE.**

:::{include} /_includes/experimental_api.md
:::

A flag that decides whether the library should treat its sources as a
site-packages layout.

When the flag is `yes`, then the `srcs` files are treated as a site-packages
layout that is relative to the `imports` attribute. The `imports` attribute
can have only a single element. It is a repo-relative runfiles path.

For example, in the `my/pkg/BUILD.bazel` file, given
`srcs=["site-packages/foo/bar.py"]`, specifying
`imports=["my/pkg/site-packages"]` means `foo/bar.py` is the file path
under the binary's venv site-packages directory that should be made available (i.e.
`import foo.bar` will work).

`__init__.py` files are treated specially to provide basic support for [implicit
namespace packages](
https://packaging.python.org/en/latest/guides/packaging-namespace-packages/#native-namespace-packages).
However, the *content* of the files cannot be taken into account, merely their
presence or absense. Stated another way: [pkgutil-style namespace packages](
https://packaging.python.org/en/latest/guides/packaging-namespace-packages/#pkgutil-style-namespace-packages)
won't be understood as namespace packages; they'll be seen as regular packages. This will
likely lead to conflicts with other targets that contribute to the namespace.

:::{tip}
This attributes populates {obj}`PyInfo.site_packages_symlinks`, which is
a topologically ordered depset. This means dependencies closer and earlier
to a consumer have precedence. See {obj}`PyInfo.site_packages_symlinks` for
more information.
:::

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
        ),
        "_add_srcs_to_runfiles_flag": lambda: attrb.Label(
            default = "//python/config_settings:add_srcs_to_runfiles",
        ),
    },
)

def _py_library_impl_with_semantics(ctx):
    return py_library_impl(
        ctx,
        semantics = create_library_semantics_struct(
            get_imports = get_imports,
            maybe_precompile = maybe_precompile,
            get_cc_info_for_library = collect_cc_info,
        ),
    )

def py_library_impl(ctx, *, semantics):
    """Abstract implementation of py_library rule.

    Args:
        ctx: The rule ctx
        semantics: A `LibrarySemantics` struct; see `create_library_semantics_struct`

    Returns:
        A list of modern providers to propagate.
    """
    direct_sources = filter_to_py_srcs(ctx.files.srcs)

    precompile_result = semantics.maybe_precompile(ctx, direct_sources)

    required_py_files = precompile_result.keep_srcs
    required_pyc_files = []
    implicit_pyc_files = []
    implicit_pyc_source_files = direct_sources

    precompile_attr = ctx.attr.precompile
    precompile_flag = ctx.attr._precompile_flag[BuildSettingInfo].value
    if (precompile_attr == PrecompileAttr.ENABLED or
        precompile_flag == PrecompileFlag.FORCE_ENABLED):
        required_pyc_files.extend(precompile_result.pyc_files)
    else:
        implicit_pyc_files.extend(precompile_result.pyc_files)

    default_outputs = builders.DepsetBuilder()
    default_outputs.add(precompile_result.keep_srcs)
    default_outputs.add(required_pyc_files)
    default_outputs = default_outputs.build()

    runfiles = builders.RunfilesBuilder()
    if AddSrcsToRunfilesFlag.is_enabled(ctx):
        runfiles.add(required_py_files)
    runfiles.add(collect_runfiles(ctx))
    runfiles = runfiles.build(ctx)

    imports = []
    site_packages_symlinks = []

    imports, site_packages_symlinks = _get_imports_and_site_packages_symlinks(ctx, semantics)

    cc_info = semantics.get_cc_info_for_library(ctx)
    py_info, deps_transitive_sources, builtins_py_info = create_py_info(
        ctx,
        original_sources = direct_sources,
        required_py_files = required_py_files,
        required_pyc_files = required_pyc_files,
        implicit_pyc_files = implicit_pyc_files,
        implicit_pyc_source_files = implicit_pyc_source_files,
        imports = imports,
        site_packages_symlinks = site_packages_symlinks,
    )

    # TODO(b/253059598): Remove support for extra actions; https://github.com/bazelbuild/bazel/issues/16455
    listeners_enabled = _py_builtins.are_action_listeners_enabled(ctx)
    if listeners_enabled:
        _py_builtins.add_py_extra_pseudo_action(
            ctx = ctx,
            dependency_transitive_python_sources = deps_transitive_sources,
        )

    providers = [
        DefaultInfo(files = default_outputs, runfiles = runfiles),
        py_info,
        create_instrumented_files_info(ctx),
        PyCcLinkParamsInfo(cc_info = cc_info),
        create_output_group_info(py_info.transitive_sources, extra_groups = {}),
    ]
    if builtins_py_info:
        providers.append(builtins_py_info)
    return providers

_DEFAULT_PY_LIBRARY_DOC = """
A library of Python code that can be depended upon.

Default outputs:
* The input Python sources
* The precompiled artifacts from the sources.

NOTE: Precompilation affects which of the default outputs are included in the
resulting runfiles. See the precompile-related attributes and flags for
more information.

:::{versionchanged} 0.37.0
Source files are no longer added to the runfiles directly.
:::
"""

def _get_imports_and_site_packages_symlinks(ctx, semantics):
    imports = depset()
    site_packages_symlinks = depset()
    if VenvsSitePackages.is_enabled(ctx):
        site_packages_symlinks = _get_site_packages_symlinks(ctx)
    else:
        imports = collect_imports(ctx, semantics)
    return imports, site_packages_symlinks

def _get_site_packages_symlinks(ctx):
    imports = ctx.attr.imports
    if len(imports) == 0:
        fail("When venvs_site_packages is enabled, exactly one `imports` " +
             "value must be specified, got 0")
    elif len(imports) > 1:
        fail("When venvs_site_packages is enabled, exactly one `imports` " +
             "value must be specified, got {}".format(imports))
    else:
        site_packages_root = imports[0]

    if site_packages_root.endswith("/"):
        fail("The site packages root value from `imports` cannot end in " +
             "slash, got {}".format(site_packages_root))
    if site_packages_root.startswith("/"):
        fail("The site packages root value from `imports` cannot start with " +
             "slash, got {}".format(site_packages_root))

    # Append slash to prevent incorrectly prefix-string matches
    site_packages_root += "/"

    # We have to build a list of (runfiles path, site-packages path) pairs of
    # the files to create in the consuming binary's venv site-packages directory.
    # To minimize the number of files to create, we just return the paths
    # to the directories containing the code of interest.
    #
    # However, namespace packages complicate matters: multiple
    # distributions install in the same directory in site-packages. This
    # works out because they don't overlap in their files. Typically, they
    # install to different directories within the namespace package
    # directory. Namespace package directories are simply directories
    # within site-packages that *don't* have an `__init__.py` file, which
    # can be arbitrarily deep. Thus, we simply have to look for the
    # directories that _do_ have an `__init__.py` file and treat those as
    # the path to symlink to.

    repo_runfiles_dirname = None
    dirs_with_init = {}  # dirname -> runfile path
    for src in ctx.files.srcs:
        if src.extension not in PYTHON_FILE_EXTENSIONS:
            continue
        path = _repo_relative_short_path(src.short_path)
        if not path.startswith(site_packages_root):
            continue
        path = path.removeprefix(site_packages_root)
        dir_name, _, filename = path.rpartition("/")
        if not dir_name:
            # This would be e.g. `site-packages/__init__.py`, which isn't valid
            # because it's not within a directory for an importable Python package.
            # However, the pypi integration over-eagerly adds a pkgutil-style
            # __init__.py file during the repo phase. Just ignore them for now.
            continue

        if filename.startswith("__init__."):
            dirs_with_init[dir_name] = None
            repo_runfiles_dirname = runfiles_root_path(ctx, src.short_path).partition("/")[0]

    # Sort so that we encounter `foo` before `foo/bar`. This ensures we
    # see the top-most explicit package first.
    dirnames = sorted(dirs_with_init.keys())
    first_level_explicit_packages = []
    for d in dirnames:
        is_sub_package = False
        for existing in first_level_explicit_packages:
            # Suffix with / to prevent foo matching foobar
            if d.startswith(existing + "/"):
                is_sub_package = True
                break
        if not is_sub_package:
            first_level_explicit_packages.append(d)

    site_packages_symlinks = []
    for dirname in first_level_explicit_packages:
        site_packages_symlinks.append((
            paths.join(repo_runfiles_dirname, site_packages_root, dirname),
            dirname,
        ))
    return site_packages_symlinks

def _repo_relative_short_path(short_path):
    # Convert `../+pypi+foo/some/file.py` to `some/file.py`
    if short_path.startswith("../"):
        return short_path[3:].partition("/")[2]
    else:
        return short_path

# NOTE: Exported publicaly
def create_py_library_rule_builder():
    """Create a rule builder for a py_library.

    :::{include} /_includes/volatile_api.md
    :::

    :::{versionadded} 1.3.0
    :::

    Returns:
        {type}`ruleb.Rule` with the necessary settings
        for creating a `py_library` rule.
    """
    builder = ruleb.Rule(
        implementation = _py_library_impl_with_semantics,
        doc = _DEFAULT_PY_LIBRARY_DOC,
        exec_groups = dict(REQUIRED_EXEC_GROUP_BUILDERS),
        attrs = LIBRARY_ATTRS,
        fragments = ["py"],
        toolchains = [
            ruleb.ToolchainType(TOOLCHAIN_TYPE, mandatory = False),
            ruleb.ToolchainType(EXEC_TOOLS_TOOLCHAIN_TYPE, mandatory = False),
        ],
    )
    return builder
