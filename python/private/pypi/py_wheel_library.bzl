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
load(
    "//python/private:py_info.bzl",
    "PyInfo",
    "VenvSymlinkEntry",
    "VenvSymlinkKind",
)
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
load(":parse_whl_name.bzl", "parse_whl_name")
load(":py_installed_wheel_info.bzl", "PyInstalledWheelInfo")
load(":py_sdist_wheel.bzl", "PyBuiltWheelInfo")

PY_WHEEL_LIBRARY_ATTRS = COMMON_ATTRS | WINDOWS_CONSTRAINTS_ATTRS | {
    "data_exclude": lambda: attrb.StringList(
        default = [],
        doc = """
Glob patterns to exclude from non-.py files when extracting the wheel.
""",
    ),
    "deps": PY_SRCS_ATTRS["deps"],
    "distribution": lambda: attrb.String(
        default = "",
        doc = "Optional Python distribution name; overrides `PyBuiltWheelInfo.distribution` and `pypi_name=` tag.",
    ),
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
    "post_install_patch_strip": lambda: attrb.Int(
        default = 0,
        doc = """
Number of leading path components to strip when applying `post_install_patches`
(for example, set to `1` to strip `a/` and `b/` from git-formatted diffs).
""",
    ),
    "post_install_patches": lambda: attrb.LabelList(
        allow_files = True,
        default = [],
        doc = """
Unified diff patch files to apply against the installed wheel's `site-packages/`
directory after extracting the wheel. Git-formatted diffs (`a/` and `b/`
prefixes) require `post_install_patch_strip = 1`.
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
    "site_paths": lambda: attrb.StringList(
        default = [],
        doc = """
Top-level or leaf paths under `site-packages/` when `extracted_files` is not
populated (e.g. for action-built sdists). Only used when `venvs_site_packages=yes`.
""",
    ),
    "srcs_exclude": lambda: attrb.StringList(
        default = [],
        doc = "Glob patterns to exclude from .py files when extracting the wheel.",
    ),
    "version": lambda: attrb.String(
        default = "",
        doc = "Optional PEP 440 package version; overrides `PyBuiltWheelInfo.version` and `pypi_version=` tag.",
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

def _expected_site_paths_from_extracted(extracted_files):
    seen = {}
    for f in extracted_files:
        if not f.startswith("site-packages/"):
            continue
        top = f[len("site-packages/"):].partition("/")[0]
        if top and not top.endswith(".dist-info"):
            seen[top] = True
    return seen.keys()

def _add_precompile_args(ctx, args, out_short_path, exec_tools_toolchain, invalidation_mode, source_retention):
    target_runtime = ctx.toolchains[TARGET_TOOLCHAIN_TYPE].py3_runtime
    version_info = target_runtime.interpreter_version_info
    python_version = "{}.{}".format(version_info.major, version_info.minor)
    args.add("--precompile")
    args.add("--pyc-tag", target_runtime.pyc_tag)
    args.add("--precompile-invalidation-mode", invalidation_mode)
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

def _expand_py_entry(path, keep_source, should_precompile, pyc_tag):
    if not keep_source:
        return [path[:-len(".py")] + ".pyc"]
    if not (should_precompile and pyc_tag):
        return [path]
    stem = paths.basename(path)[:-len(".py")]
    dirname = paths.dirname(path)
    pyc_rel = (
        "{}/__pycache__/{}.{}.pyc".format(dirname, stem, pyc_tag) if dirname else "__pycache__/{}.{}.pyc".format(stem, pyc_tag)
    )
    return [path, pyc_rel]

def _resolve_meta_value(explicit_val, built_val, tag_val, whl_val, use_site_paths):
    if explicit_val:
        return explicit_val
    if built_val:
        return built_val
    if use_site_paths:
        return whl_val
    return tag_val or whl_val

def _collect_installed_tree_files(
        extracted_files,
        shebang_scripts,
        *,
        is_windows,
        keep_source,
        should_precompile,
        pyc_tag):
    tree_files = []
    for f in extracted_files:
        if f.startswith("site-packages/") and f.endswith(".py"):
            tree_files.extend(_expand_py_entry(f, keep_source, should_precompile, pyc_tag))
        else:
            tree_files.append(f)
    for s in shebang_scripts:
        tree_files.append("bin/" + ((s + ".bat") if is_windows else s))
    return tree_files

def _venv_symlinks_for_site_paths(
        ctx,
        out_files,
        out_rf_path,
        site_packages_rf_path,
        package,
        version_str,
        dist_info_dir,
        is_windows,
        keep_source,
        should_precompile = False,
        pyc_tag = ""):
    symlinks = []
    seen = {}
    entries = []
    for sp in list(ctx.attr.site_paths) + list(ctx.attr.namespace_package_files):
        if sp.endswith(".py"):
            entries.extend(_expand_py_entry(sp, keep_source, should_precompile, pyc_tag))
        else:
            entries.append(sp)
    if dist_info_dir:
        entries.append(dist_info_dir)
    for sp in entries:
        if not sp or sp in seen:
            continue
        seen[sp] = True
        symlinks.append(VenvSymlinkEntry(
            kind = VenvSymlinkKind.LIB,
            link_to_path = paths.join(site_packages_rf_path, sp),
            link_to_file = None,
            package = package,
            version = version_str,
            venv_path = sp,
            files = out_files,
        ))
    for s in ctx.attr.shebang_scripts:
        script_name = (s + ".bat") if is_windows else s
        symlinks.append(VenvSymlinkEntry(
            kind = VenvSymlinkKind.BIN,
            link_to_path = paths.join(out_rf_path, "bin", script_name),
            link_to_file = None,
            package = package,
            version = version_str,
            venv_path = script_name,
            files = out_files,
        ))
    return symlinks

def _compute_wheel_venv_symlinks(
        ctx,
        out,
        out_rf_path,
        site_packages_rf_path,
        *,
        package,
        version_str,
        dist_info_dir,
        is_windows,
        should_precompile,
        keep_source):
    pyc_tag = (
        ctx.toolchains[TARGET_TOOLCHAIN_TYPE].py3_runtime.pyc_tag if should_precompile else ""
    )
    if ctx.attr.extracted_files:
        tree_files = _collect_installed_tree_files(
            ctx.attr.extracted_files,
            ctx.attr.shebang_scripts,
            is_windows = is_windows,
            keep_source = keep_source,
            should_precompile = should_precompile,
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
    else:
        venv_symlinks = _venv_symlinks_for_site_paths(
            ctx,
            depset([out]),
            out_rf_path,
            site_packages_rf_path,
            package,
            version_str,
            dist_info_dir,
            is_windows,
            keep_source,
            should_precompile = should_precompile,
            pyc_tag = pyc_tag,
        )
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

def _run_wheel_install_action(
        ctx,
        *,
        built_info,
        installed_info,
        dist_info_dir,
        use_site_paths,
        effective_srcs_exclude,
        effective_data_exclude,
        is_windows,
        create_namespace_inits,
        venvs_site_packages_enabled,
        should_precompile,
        invalidation_mode,
        source_retention,
        keep_source,
        exec_tools_toolchain):
    out = ctx.actions.declare_directory(ctx.attr.name)
    entry_points_out = ctx.actions.declare_file(ctx.attr.name + ".dist_info/entry_points.txt")
    wheel_input = built_info.directory if built_info != None else ctx.file.wheel
    args = ctx.actions.args()

    if installed_info != None and installed_info.wheel == None:
        if not installed_info.keep_source and (keep_source or ctx.files.post_install_patches):
            fail(
                "Cannot apply post_install_patches or restore .py sources from '{}' because its .py sources were omitted (precompile_source_retention = 'omit_source')".format(
                    ctx.attr.wheel.label,
                ),
            )
        args.add_all("--installed-dir", [installed_info.directory], expand_directories = False)
        install_source_file = installed_info.directory
        underlying_wheel = None
    else:
        install_source_file = (
            installed_info.wheel if installed_info != None else wheel_input
        )
        args.add_all("--wheel", [install_source_file], expand_directories = False)
        underlying_wheel = None if ctx.files.post_install_patches else install_source_file

    args.add_all("--directory", [out], expand_directories = False)
    args.add("--entry-points-output", entry_points_out)
    args.add("--target-os", "windows" if is_windows else "unix")
    if dist_info_dir:
        args.add("--dist-info-dir", dist_info_dir)
    for pattern in effective_srcs_exclude:
        args.add("--srcs-exclude-glob", pattern)
    for pattern in effective_data_exclude:
        args.add("--data-exclude-glob", pattern)
    if create_namespace_inits:
        args.add("--create-namespace-inits")
    if ctx.files.post_install_patches:
        args.add("--patch-strip", str(ctx.attr.post_install_patch_strip))
        for patch_file in ctx.files.post_install_patches:
            args.add("--patch", patch_file)
    if venvs_site_packages_enabled:
        args.add("--validate-site-packages")
        args.add("--validation-source", "site_paths" if use_site_paths else "extracted_files")
        expected_paths = (
            ctx.attr.site_paths + ctx.attr.namespace_package_files if use_site_paths else _expected_site_paths_from_extracted(ctx.attr.extracted_files)
        )
        for sp in expected_paths:
            args.add("--expected-site-path", sp)

    extra_tools = []
    if should_precompile:
        extra_tools = _add_precompile_args(
            ctx,
            args,
            out.short_path,
            exec_tools_toolchain,
            invalidation_mode,
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
        inputs = [install_source_file] + ctx.files.post_install_patches + helper_files,
        outputs = [out, entry_points_out],
        tools = extra_tools,
        mnemonic = "PyWheelInstall",
        progress_message = "Installing wheel {} into %{{output}}".format(install_source_file.basename),
    )
    return out, entry_points_out, underlying_wheel

def _py_wheel_library_impl(ctx):
    exec_tools_toolchain = ctx.toolchains[EXEC_TOOLS_TOOLCHAIN_TYPE]
    if exec_tools_toolchain == None:
        fail(
            "experimental_action_install requires the exec_tools toolchain " +
            "(set //python/config_settings:exec_tools_toolchain=enabled)",
        )

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
    invalidation_mode = _resolve_invalidation_mode(ctx) if should_precompile else ""

    built_info = (
        ctx.attr.wheel[PyBuiltWheelInfo] if PyBuiltWheelInfo in ctx.attr.wheel else None
    )
    tag_package, tag_version = _get_package_and_version(
        ctx.attr.extracted_files,
        ctx.attr.tags,
    )
    whl_package = None
    whl_version = None
    if built_info == None and ctx.file.wheel.basename.endswith(".whl") and ctx.file.wheel.basename.count("-") >= 4:
        parsed_whl = parse_whl_name(ctx.file.wheel.basename)
        whl_package = normalize_name(parsed_whl.distribution)
        parsed_ver = version.parse(parsed_whl.version, strict = False)
        whl_version = parsed_ver.string if parsed_ver else None

    use_site_paths = bool(ctx.attr.site_paths) or not ctx.attr.extracted_files
    package = _resolve_meta_value(
        normalize_name(ctx.attr.distribution) if ctx.attr.distribution else None,
        built_info.distribution if built_info else None,
        tag_package,
        whl_package,
        use_site_paths,
    )
    version_str = _resolve_meta_value(
        version.normalize(ctx.attr.version) if ctx.attr.version else None,
        built_info.version if built_info else None,
        tag_version,
        whl_version,
        use_site_paths,
    )
    if (ctx.attr.site_paths or (venvs_site_packages_enabled and use_site_paths)) and (not package or not version_str):
        fail(
            "py_wheel_library requires distribution and version (via PyBuiltWheelInfo " +
            "or the distribution and version attributes) when site_paths is used or " +
            "extracted_files is empty in venvs_site_packages mode",
        )
    dist_info_dir = (
        "{}-{}.dist-info".format(package, version_str) if use_site_paths and package and version_str else ""
    )

    installed_info = (
        ctx.attr.wheel[PyInstalledWheelInfo] if PyInstalledWheelInfo in ctx.attr.wheel else None
    )
    effective_srcs_exclude = list(ctx.attr.srcs_exclude)
    effective_data_exclude = list(ctx.attr.data_exclude)
    if installed_info != None:
        for p in installed_info.settings_key[4]:
            if p not in effective_srcs_exclude:
                effective_srcs_exclude.append(p)
        for p in installed_info.settings_key[5]:
            if p not in effective_data_exclude:
                effective_data_exclude.append(p)

    settings_key = (
        should_precompile,
        keep_source,
        invalidation_mode,
        ctx.attr.precompile_optimize_level if should_precompile else 0,
        tuple(effective_srcs_exclude),
        tuple(effective_data_exclude),
        create_namespace_inits,
        dist_info_dir,
    )

    can_reuse_installed = (
        installed_info != None and
        installed_info.entry_points != None and
        not ctx.files.post_install_patches and
        installed_info.settings_key == settings_key
    )
    if can_reuse_installed:
        out = installed_info.directory
        entry_points_out = installed_info.entry_points
        underlying_wheel = installed_info.wheel
    else:
        out, entry_points_out, underlying_wheel = _run_wheel_install_action(
            ctx,
            built_info = built_info,
            installed_info = installed_info,
            dist_info_dir = dist_info_dir,
            use_site_paths = use_site_paths,
            effective_srcs_exclude = effective_srcs_exclude,
            effective_data_exclude = effective_data_exclude,
            is_windows = is_windows,
            create_namespace_inits = create_namespace_inits,
            venvs_site_packages_enabled = venvs_site_packages_enabled,
            should_precompile = should_precompile,
            invalidation_mode = invalidation_mode,
            source_retention = source_retention,
            keep_source = keep_source,
            exec_tools_toolchain = exec_tools_toolchain,
        )

    out_rf_path = runfiles_root_path(ctx, out.short_path)
    site_packages_rf_path = paths.join(out_rf_path, "site-packages")

    if venvs_site_packages_enabled:
        imports = depset()
        venv_symlinks = _compute_wheel_venv_symlinks(
            ctx,
            out,
            out_rf_path,
            site_packages_rf_path,
            package = package,
            version_str = version_str,
            dist_info_dir = dist_info_dir,
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
    has_pyi = (
        _has_pyi_files(ctx.attr.extracted_files, keep_source = keep_source) or
        _has_pyi_files(
            ["site-packages/" + sp.strip("/") for sp in ctx.attr.site_paths if sp.strip("/")],
            keep_source = keep_source,
        )
    )
    py_info, builtins_py_info = create_py_info(
        ctx,
        original_sources = [out],
        required_py_files = [out] if keep_source else [],
        required_pyc_files = [out] if should_precompile else [],
        implicit_pyc_files = [],
        implicit_pyc_source_files = [],
        imports = imports,
        venv_symlinks = venv_symlinks,
        pyi_files = [out] if has_pyi else [],
        srcs_version = "ALL",
        pyi_deps = [],
    )

    providers = [
        DefaultInfo(files = depset([out]), runfiles = runfiles),
        py_info,
        PyInstalledWheelInfo(
            directory = out,
            entry_points = entry_points_out,
            keep_source = keep_source,
            precompiled = should_precompile,
            settings_key = settings_key,
            wheel = underlying_wheel,
        ),
        create_instrumented_files_info(ctx, source_attributes = []),
        PyCcLinkParamsInfo(cc_info = cc_info),
        create_output_group_info(
            py_info.transitive_sources,
            extra_groups = {"dist_info": depset([entry_points_out])},
        ),
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
`.pyi` stubs or `py.typed` markers are present in `extracted_files` (or
explicitly listed in `site_paths` for action-built sdists; `py.typed` without
`.pyi` files is ignored when sources are omitted), `PyInfo.direct_pyi_files` /
`transitive_pyi_files` contains the installed wheel `TreeArtifact` directory;
consumers must handle directory `File`s. For action-built sdists whose
`site_paths` only list package directory names, `pyi_files` is empty unless
`.pyi` or `py.typed` paths are included in `site_paths`.
:::
""",
    attrs = PY_WHEEL_LIBRARY_ATTRS,
    provides = [PyCcLinkParamsInfo, PyInfo, PyInstalledWheelInfo] + _MaybeBuiltinPyInfo,
    toolchains = [
        ruleb.ToolchainType(TARGET_TOOLCHAIN_TYPE, mandatory = False),
        ruleb.ToolchainType(EXEC_TOOLS_TOOLCHAIN_TYPE, mandatory = False),
    ],
).build()
