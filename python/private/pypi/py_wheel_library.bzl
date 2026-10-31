"""Rule for extracting and installing a Python wheel in a Bazel build action."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//python/private:attr_builders.bzl", "attrb")
load(
    "//python/private:attributes.bzl",
    "COMMON_ATTRS",
    "PY_SRCS_ATTRS",
    "PrecompileAttr",
    "PrecompileInvalidationModeAttr",
    "PrecompileSourceRetentionAttr",
    "WINDOWS_CONSTRAINTS_ATTRS",
)
load("//python/private:builders.bzl", "builders")
load(
    "//python/private:common.bzl",
    "actions_run",
    "collect_cc_info",
    "collect_runfiles",
    "create_instrumented_files_info",
    "create_output_group_info",
    "create_py_info",
    "is_windows_platform",
    "runfiles_root_path",
)
load(
    "//python/private:flags.bzl",
    "CompilationMode",
    "VenvsSitePackages",
)
load("//python/private:normalize_name.bzl", "normalize_name")
load("//python/private:py_cc_link_params_info.bzl", "PyCcLinkParamsInfo")
load("//python/private:py_info.bzl", "PyInfo")
load("//python/private:py_interpreter_program.bzl", "PyInterpreterProgramInfo")
load("//python/private:py_library.bzl", "LIBRARY_ATTRS")
load("//python/private:reexports.bzl", "BuiltinPyInfo")
load("//python/private:rule_builders.bzl", "ruleb")
load(
    "//python/private:toolchain_types.bzl",
    "EXEC_TOOLS_TOOLCHAIN_TYPE",
    "TARGET_TOOLCHAIN_TYPE",
)
load("//python/private:venv_runfiles.bzl", "get_venv_symlinks")
load("//python/private:version.bzl", "version")

PY_WHEEL_LIBRARY_ATTRS = COMMON_ATTRS | WINDOWS_CONSTRAINTS_ATTRS | {
    "data_exclude": lambda: attrb.StringList(
        default = [],
        doc = """
Glob patterns to exclude from non-.py files when extracting the wheel.
""",
    ),
    "deps": PY_SRCS_ATTRS["deps"],
    "enable_implicit_namespace_pkgs": lambda: attrb.Bool(
        default = False,
        doc = """
If True, disables generating pkgutil-style __init__.py files for implicit
namespace packages.
""",
    ),
    "experimental_venvs_site_packages": LIBRARY_ATTRS["experimental_venvs_site_packages"],
    "extracted_files": lambda: attrb.StringList(
        default = [],
        doc = "Relative paths under the installed wheel directory.",
    ),
    "namespace_package_files": lambda: attrb.StringList(
        default = [],
        doc = """
Relative paths to pkgutil-style namespace package __init__.py files.
""",
    ),
    "precompile": PY_SRCS_ATTRS["precompile"],
    "precompile_invalidation_mode": PY_SRCS_ATTRS["precompile_invalidation_mode"],
    "precompile_optimize_level": PY_SRCS_ATTRS["precompile_optimize_level"],
    "precompile_source_retention": PY_SRCS_ATTRS["precompile_source_retention"],
    "shebang_scripts": lambda: attrb.StringList(
        default = [],
        doc = """
Top-level script names in .data/scripts/ whose #!python shebang is rewritten.
""",
    ),
    "srcs_exclude": lambda: attrb.StringList(
        default = [],
        doc = "Glob patterns to exclude from .py files when extracting the wheel.",
    ),
    "wheel": lambda: attrb.Label(
        allow_single_file = True,
        mandatory = True,
        doc = "The .whl file to extract and install.",
    ),
    "_action_whl_installer": lambda: attrb.Label(
        cfg = "exec",
        default = Label("//python/private/pypi:action_whl_installer"),
    ),
    "_action_whl_installer_helpers": lambda: attrb.Label(
        allow_files = True,
        default = Label("//python/private/pypi:action_whl_installer_helpers"),
    ),
    "_precompile_flag": PY_SRCS_ATTRS["_precompile_flag"],
    "_precompile_source_retention_flag": PY_SRCS_ATTRS["_precompile_source_retention_flag"],
}

def _has_pyi_files(extracted_files, keep_source = True):
    for f in extracted_files:
        if not f.startswith("site-packages/"):
            continue
        if f.endswith(".pyi"):
            return True
        if keep_source and (f == "site-packages/py.typed" or f.endswith("/py.typed")):
            return True
    return False

def _should_precompile(ctx, exec_tools_toolchain):
    if exec_tools_toolchain.exec_tools.precompiler == None:
        return False
    target_toolchain = ctx.toolchains[TARGET_TOOLCHAIN_TYPE]

    # Builtin / custom toolchains may omit py3_runtime, pyc_tag, or
    # interpreter_version_info (e.g. BuiltinPyRuntimeInfo).
    if target_toolchain == None:
        return False
    if not hasattr(target_toolchain, "py3_runtime") or not target_toolchain.py3_runtime:
        return False
    target_runtime = target_toolchain.py3_runtime
    if not hasattr(target_runtime, "pyc_tag") or not target_runtime.pyc_tag:
        return False
    if (
        not hasattr(target_runtime, "interpreter_version_info") or
        not target_runtime.interpreter_version_info
    ):
        return False
    return PrecompileAttr.get_effective_value(ctx) == PrecompileAttr.ENABLED

def _get_package_and_version(extracted_files, tags):
    dist_info_dir = None
    for f in extracted_files:
        parts = f.split("/")
        if (
            len(parts) == 3 and
            parts[0] == "site-packages" and
            parts[1].endswith(".dist-info") and
            parts[2].lower() == "metadata"
        ):
            dist_info_dir = parts[1]
            break

    if dist_info_dir:
        stem = dist_info_dir.removesuffix(".dist-info")
        package, _, version_str = stem.rpartition("-")
        if package and version_str:
            return normalize_name(package), version.normalize(version_str)

    package = None
    version_str = None
    for tag in tags:
        if tag.startswith("pypi_name="):
            package = normalize_name(tag[len("pypi_name="):])
        elif tag.startswith("pypi_version="):
            version_str = version.normalize(tag[len("pypi_version="):])
    return package, version_str

def _resolve_invalidation_mode(ctx):
    mode = ctx.attr.precompile_invalidation_mode
    if mode != PrecompileInvalidationModeAttr.AUTO:
        return mode
    if ctx.var.get("COMPILATION_MODE") == CompilationMode.OPT:
        return PrecompileInvalidationModeAttr.UNCHECKED_HASH
    return PrecompileInvalidationModeAttr.CHECKED_HASH

def _add_precompile_args(ctx, args, out_short_path, exec_tools_toolchain, source_retention):
    target_runtime = ctx.toolchains[TARGET_TOOLCHAIN_TYPE].py3_runtime
    version_info = target_runtime.interpreter_version_info
    python_version = "{}.{}".format(version_info.major, version_info.minor)
    args.add("--precompile")
    args.add("--pyc-tag", target_runtime.pyc_tag)
    args.add("--precompile-invalidation-mode", _resolve_invalidation_mode(ctx))
    args.add("--precompile-optimize-level", str(ctx.attr.precompile_optimize_level))
    args.add("--precompile-source-retention", source_retention)
    args.add("--python-version", python_version)
    args.add("--src-name-prefix", out_short_path)

    precompiler = exec_tools_toolchain.exec_tools.precompiler

    # When the precompiler provides PyInterpreterProgramInfo (the default stock
    # precompiler), action_whl_installer compiles in-process using the exec_tools
    # interpreter directly.
    if PyInterpreterProgramInfo in precompiler:
        return []

    files_to_run = precompiler[DefaultInfo].files_to_run
    if not files_to_run or not files_to_run.executable:
        fail(("Unrecognized precompiler: target '{}' does not provide " +
              "PyInterpreterProgramInfo nor appears to be executable").format(
            precompiler,
        ))
    args.add("--precompiler-tool", files_to_run.executable)
    return [files_to_run]

def _collect_installed_tree_files(
        extracted_files,
        shebang_scripts,
        *,
        is_windows,
        keep_source,
        pyc_tag):
    tree_files = []
    for f in extracted_files:
        is_site_py = f.startswith("site-packages/") and f.endswith(".py")
        if not is_site_py:
            tree_files.append(f)
            continue
        if not keep_source:
            tree_files.append(f[:-len(".py")] + ".pyc")
            continue
        tree_files.append(f)
        if pyc_tag:
            stem = paths.basename(f)[:-len(".py")]
            tree_files.append(
                "{}/__pycache__/{}.{}.pyc".format(paths.dirname(f), stem, pyc_tag),
            )
    for s in shebang_scripts:
        tree_files.append("bin/" + ((s + ".bat") if is_windows else s))
    return tree_files

def _compute_wheel_venv_symlinks(
        ctx,
        out,
        *,
        is_windows,
        should_precompile,
        keep_source):
    package, version_str = _get_package_and_version(
        ctx.attr.extracted_files,
        ctx.attr.tags,
    )
    pyc_tag = (
        ctx.toolchains[TARGET_TOOLCHAIN_TYPE].py3_runtime.pyc_tag if should_precompile else ""
    )
    tree_files = _collect_installed_tree_files(
        ctx.attr.extracted_files,
        ctx.attr.shebang_scripts,
        is_windows = is_windows,
        keep_source = keep_source,
        pyc_tag = pyc_tag,
    )
    venv_symlinks = list(get_venv_symlinks(
        ctx,
        tree_files,
        package,
        version_str,
        site_packages_root = "site-packages",
        namespace_package_files = ctx.attr.namespace_package_files,
        tree_artifact = out,
    ))
    extra_data_files = [f for f in ctx.files.data if not f.is_directory]
    if extra_data_files:
        site_packages_root = paths.normalize(paths.join(
            ctx.label.package,
            "site-packages",
        ))
        venv_symlinks.extend(get_venv_symlinks(
            ctx,
            extra_data_files,
            package,
            version_str,
            site_packages_root = site_packages_root,
        ))
    return venv_symlinks

def _py_wheel_library_impl(ctx):
    exec_tools_toolchain = ctx.toolchains[EXEC_TOOLS_TOOLCHAIN_TYPE]
    if exec_tools_toolchain == None:
        fail(
            "experimental_action_install requires the exec_tools toolchain " +
            "(set //python/config_settings:exec_tools_toolchain=enabled)",
        )

    out = ctx.actions.declare_directory(ctx.attr.name)
    is_windows = is_windows_platform(ctx)
    venvs_site_packages_enabled = VenvsSitePackages.is_enabled(ctx)
    create_namespace_inits = (
        not ctx.attr.enable_implicit_namespace_pkgs and
        not venvs_site_packages_enabled
    )
    should_precompile = _should_precompile(ctx, exec_tools_toolchain)
    source_retention = PrecompileSourceRetentionAttr.get_effective_value(ctx)
    keep_source = (
        not should_precompile or
        source_retention == PrecompileSourceRetentionAttr.KEEP_SOURCE
    )

    args = ctx.actions.args()
    args.add("--wheel", ctx.file.wheel)
    args.add_all("--directory", [out], expand_directories = False)
    args.add("--target-os", "windows" if is_windows else "unix")
    for pattern in ctx.attr.srcs_exclude:
        args.add("--srcs-exclude-glob", pattern)
    for pattern in ctx.attr.data_exclude:
        args.add("--data-exclude-glob", pattern)
    if create_namespace_inits:
        args.add("--create-namespace-inits")

    extra_tools = []
    if should_precompile:
        extra_tools = _add_precompile_args(
            ctx,
            args,
            out.short_path,
            exec_tools_toolchain,
            source_retention,
        )

    helper_files = ctx.files._action_whl_installer_helpers
    actions_run(
        ctx,
        executable = ctx.attr._action_whl_installer,
        arguments = [args],
        env = {
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONPATH": helper_files[0].dirname,
        },
        inputs = [ctx.file.wheel] + helper_files,
        outputs = [out],
        tools = extra_tools,
        mnemonic = "PyWheelInstall",
        progress_message = "Installing wheel {} into %{{output}}".format(ctx.file.wheel.basename),
    )

    out_rf_path = runfiles_root_path(ctx, out.short_path)
    site_packages_rf_path = paths.join(out_rf_path, "site-packages")

    if venvs_site_packages_enabled:
        imports = depset()
        venv_symlinks = _compute_wheel_venv_symlinks(
            ctx,
            out,
            is_windows = is_windows,
            should_precompile = should_precompile,
            keep_source = keep_source,
        )
    else:
        imports = depset([site_packages_rf_path])
        venv_symlinks = []

    runfiles = builders.RunfilesBuilder()
    runfiles.add([out])
    runfiles.add(collect_runfiles(ctx))
    runfiles = runfiles.build(ctx)

    cc_info = collect_cc_info(ctx)
    py_info, builtins_py_info = create_py_info(
        ctx,
        original_sources = [out],
        required_py_files = [out] if keep_source else [],
        required_pyc_files = [out] if should_precompile else [],
        implicit_pyc_files = [],
        implicit_pyc_source_files = [],
        imports = imports,
        venv_symlinks = venv_symlinks,
        pyi_files = [out] if _has_pyi_files(ctx.attr.extracted_files, keep_source = keep_source) else [],
        srcs_version = "ALL",
        pyi_deps = [],
    )

    providers = [
        DefaultInfo(files = depset([out]), runfiles = runfiles),
        py_info,
        create_instrumented_files_info(ctx, source_attributes = []),
        PyCcLinkParamsInfo(cc_info = cc_info),
        create_output_group_info(py_info.transitive_sources, extra_groups = {}),
    ]
    if builtins_py_info:
        providers.append(builtins_py_info)
    return providers

_MaybeBuiltinPyInfo = [BuiltinPyInfo] if BuiltinPyInfo != None else []

py_wheel_library = ruleb.Rule(
    implementation = _py_wheel_library_impl,
    doc = """
Extracts and installs a Python wheel into a directory artifact during the build
phase.

:::{note}
Precompilation is performed inside the wheel installation action based on the
effective `precompile` setting (`--precompile` and `precompile`). A downstream
binary that explicitly overrides `pyc_collection` (rather than inheriting from
`--precompile`) does not change whether `.pyc` files are included in the
installed wheel directory. When a custom `PyExecToolsInfo.precompiler` binary is
configured on the exec-tools toolchain, it runs as a plain subprocess inside the
wheel installation action using its documented CLI (`@params` file); worker
settings (`--//tools/precompiler:execution_requirements` and
`testing.ExecutionInfo`) do not apply. When `precompile_source_retention` is
`omit_source`, `.py` source files are removed from the installed wheel
`TreeArtifact` (and `PyInfo.direct_original_sources` /
`transitive_original_sources` reference that sourceless directory, so static
analysis and coverage tools will not see `.py` sources for the wheel). When
`.pyi` stubs or `py.typed` markers are present (`py.typed` without `.pyi` files
is ignored when sources are omitted), `PyInfo.direct_pyi_files` /
`transitive_pyi_files` contains the installed wheel `TreeArtifact` directory;
consumers must handle directory `File`s.
:::
""",
    attrs = PY_WHEEL_LIBRARY_ATTRS,
    provides = [PyCcLinkParamsInfo, PyInfo] + _MaybeBuiltinPyInfo,
    toolchains = [
        ruleb.ToolchainType(TARGET_TOOLCHAIN_TYPE, mandatory = False),
        ruleb.ToolchainType(EXEC_TOOLS_TOOLCHAIN_TYPE, mandatory = False),
    ],
).build()
