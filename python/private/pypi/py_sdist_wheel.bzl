"""Rule for building a Python wheel (.whl) from an sdist archive in a Bazel build action."""

load("//python/private:attr_builders.bzl", "attrb")
load("//python/private:attributes.bzl", "REQUIRED_EXEC_GROUP_BUILDERS")
load("//python/private:builders.bzl", "builders")
load("//python/private:common.bzl", "actions_run")
load("//python/private:normalize_name.bzl", "normalize_name")
load("//python/private:py_info.bzl", "PyInfo", "VenvSymlinkKind")
load("//python/private:py_interpreter_program.bzl", "PyInterpreterProgramInfo")
load("//python/private:reexports.bzl", "BuiltinPyInfo")
load("//python/private:rule_builders.bzl", "ruleb")
load(
    "//python/private:toolchain_types.bzl",
    "EXEC_TOOLS_TOOLCHAIN_TYPE",
    "TARGET_TOOLCHAIN_TYPE",
)
load("//python/private:version.bzl", "version")
load(":py_installed_wheel_info.bzl", "PyInstalledWheelInfo")

PyBuiltWheelInfo = provider(
    doc = """
Information about a wheel built in a build action.

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
    fields = {
        "directory": """
:type: File

The `.whldir` directory artifact (`TreeArtifact`) containing the built `.whl` file
with its canonical PEP 427 filename.
""",
        "distribution": """
:type: str

The normalized Python distribution name (e.g. `foo_bar`).
""",
        "version": """
:type: str

The normalized PEP 440 version string (e.g. `1.2.3`).
""",
    },
)

BOOTSTRAP_BUILD_PACKAGES = {
    "build": True,
    "installer": True,
    "more_itertools": True,
    "packaging": True,
    "pip": True,
    "pyproject_hooks": True,
    "setuptools": True,
    "tomli": True,
    "wheel": True,
}

_BOOTSTRAP_DEPS = [
    Label("@pypi__" + k + "//:lib")
    for k in BOOTSTRAP_BUILD_PACKAGES
]

_BOOTSTRAP_REPO_NAMES = {
    dep_label.repo_name: True
    for dep_label in _BOOTSTRAP_DEPS
}

_PLATFORM_CONSTRAINTS = {
    Label("@platforms//cpu:aarch32"): "cpu=arm",
    Label("@platforms//cpu:aarch64"): "cpu=aarch64",
    Label("@platforms//cpu:arm64e"): "cpu=aarch64",
    Label("@platforms//cpu:armv7"): "cpu=arm",
    Label("@platforms//cpu:i386"): "cpu=x86_32",
    Label("@platforms//cpu:ppc"): "cpu=ppc",
    Label("@platforms//cpu:ppc64le"): "cpu=ppc",
    Label("@platforms//cpu:riscv64"): "cpu=riscv64",
    Label("@platforms//cpu:s390x"): "cpu=s390x",
    Label("@platforms//cpu:x86_32"): "cpu=x86_32",
    Label("@platforms//cpu:x86_64"): "cpu=x86_64",
    Label("@platforms//os:linux"): "os=linux",
    Label("@platforms//os:macos"): "os=macos",
    Label("@platforms//os:windows"): "os=windows",
}

PY_SDIST_WHEEL_ATTRS = {
    "add_libdir_to_library_search_path": lambda: attrb.Bool(
        default = False,
        doc = """
If True, adds `-L<exec_prefix>/lib` for the build Python interpreter to `LDFLAGS`.
""",
    ),
    "build_deps": lambda: attrb.LabelList(
        cfg = "exec",
        default = [],
        doc = """
Additional build-time Python package dependencies (PEP 517 `build-system.requires`),
evaluated in the `exec` configuration. To satisfy version constraints that conflict
with the default bootstrap packages (e.g. `setuptools<70`), add the pinned package
to `build_deps`; it takes precedence.
""",
    ),
    "builder": lambda: attrb.Label(
        cfg = "exec",
        default = Label("//python/private/pypi:sdist_wheel_builder"),
        doc = """
Executable tool that builds a wheel from an sdist into a `.whldir` directory.
""",
    ),
    "config_settings": lambda: attrb.StringDict(
        default = {},
        doc = """
PEP 517 `--config-settings=KEY=VALUE` pairs passed to the wheel build.
""",
    ),
    "config_settings_list": lambda: attrb.StringListDict(
        default = {},
        doc = """
Multi-valued PEP 517 `--config-settings=KEY=VALUE` pairs passed as repeated
flags to the wheel build.
""",
    ),
    "distribution": lambda: attrb.String(
        default = "",
        doc = "Optional Python distribution name; inferred from the `sdist` filename if omitted.",
    ),
    "environment": lambda: attrb.StringDict(
        default = {},
        doc = """
Environment variables to set during the PEP 517 wheel build action. Note that
the default builder uses the host system toolchain (`use_default_shell_env`).
""",
    ),
    "pre_build_patch_strips": lambda: attrb.IntList(
        default = [],
        doc = "Optional per-patch strip counts corresponding 1:1 with `pre_build_patches`.",
    ),
    "pre_build_patches": lambda: attrb.LabelList(
        allow_files = True,
        default = [],
        doc = """
Unified diff patch files to apply to the unpacked sdist source directory before building.
Note that git-formatted patches with `a/` and `b/` path prefixes require strip `1` in
`pre_build_patch_strips`.
""",
    ),
    "sdist": lambda: attrb.Label(
        allow_single_file = True,
        mandatory = True,
        doc = "The source distribution archive (`.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz`, or `.zip`).",
    ),
    "version": lambda: attrb.String(
        default = "",
        doc = "Optional PEP 440 package version; inferred from the `sdist` filename if omitted.",
    ),
    "_bootstrap_deps": lambda: attrb.LabelList(
        cfg = "exec",
        default = _BOOTSTRAP_DEPS,
    ),
    "_platform_constraints": lambda: attrb.LabelKeyedStringDict(
        default = _PLATFORM_CONSTRAINTS,
    ),
    "_sdist_wheel_builder_helpers": lambda: attrb.Label(
        allow_files = True,
        default = Label("//python/private/pypi:sdist_wheel_builder_helpers"),
    ),
}

_SDIST_EXTS = (".tar.gz", ".tgz", ".tar.bz2", ".tar.xz", ".zip")

def _parse_sdist_filename(filename):
    stem = filename
    for ext in _SDIST_EXTS:
        if stem.endswith(ext):
            stem = stem[:-len(ext)]
            break
    dist, sep, ver = stem.rpartition("-")
    if not sep or not dist or not ver:
        return "", ""
    parsed_ver = version.parse(ver, strict = False)
    return normalize_name(dist), (parsed_ver.string if parsed_ver else "")

def _collect_deps(deps):
    files = builders.DepsetBuilder()
    sources = builders.DepsetBuilder()
    imports = builders.DepsetBuilder()
    venv_symlinks = builders.DepsetBuilder()
    for dep in deps:
        files.add(dep[DefaultInfo].files)
        if dep[DefaultInfo].default_runfiles:
            files.add(dep[DefaultInfo].default_runfiles.files)
        py = (
            dep[PyInfo] if PyInfo in dep else (dep[BuiltinPyInfo] if BuiltinPyInfo != None and BuiltinPyInfo in dep else None)
        )
        if py:
            files.add(py.transitive_sources)
            sources.add(py.transitive_sources)
            if PyInstalledWheelInfo not in dep:
                imports.add(py.imports)
                if hasattr(py, "venv_symlinks"):
                    venv_symlinks.add(py.venv_symlinks)
        if PyInstalledWheelInfo in dep:
            files.add([dep[PyInstalledWheelInfo].directory])
            sources.add([dep[PyInstalledWheelInfo].directory])
    return struct(
        files = files.build(),
        sources = sources.build(),
        imports = imports.build(),
        venv_symlinks = venv_symlinks.build(),
    )

def _dir_only(f):
    return f.path if f.is_directory else None

def _venv_symlink_import_root(entry):
    if entry.kind != VenvSymlinkKind.LIB or not entry.link_to_path or not entry.venv_path:
        return None
    suffix = "/" + entry.venv_path
    if not entry.link_to_path.endswith(suffix):
        return None
    return entry.link_to_path[:-len(suffix)]

def _non_dir_dep_file(f):
    if f.is_directory:
        return None
    if f.owner and f.owner.repo_name in _BOOTSTRAP_REPO_NAMES:
        return None
    return f.path + "=" + f.short_path

def _validate_sdist_toolchains(exec_runtime, target_runtime):
    if not (
        exec_runtime and exec_runtime.interpreter_version_info and
        target_runtime and target_runtime.interpreter_version_info
    ):
        return
    evi = exec_runtime.interpreter_version_info
    tvi = target_runtime.interpreter_version_info
    if not (evi.major and evi.minor != None and tvi.major and tvi.minor != None):
        return
    if evi.major != tvi.major or evi.minor != tvi.minor:
        fail(
            "py_sdist_wheel requires exec and target Python toolchains to have matching " +
            "major.minor versions because build_deps are built in the exec configuration " +
            "(got exec Python {}.{}, target Python {}.{})".format(
                evi.major,
                evi.minor,
                tvi.major,
                tvi.minor,
            ),
        )

def _resolve_sdist_output_names(name):
    if name.endswith(".whldir"):
        stem = name[:-len(".whldir")]
        return name, stem + ".sdist_build.whl"
    if name.endswith(".sdist_build.whl"):
        stem = name[:-len(".sdist_build.whl")]
        return stem + ".whldir", name
    if name.endswith(".whl"):
        stem = name[:-len(".whl")]
        return stem + ".whldir", name
    return name + ".whldir", name + ".sdist_build.whl"

def _py_sdist_wheel_impl(ctx):
    if ctx.attr.add_libdir_to_library_search_path and "LDFLAGS" in ctx.attr.environment:
        fail("Can't set both environment LDFLAGS and add_libdir_to_library_search_path")
    patches = ctx.files.pre_build_patches
    strips = ctx.attr.pre_build_patch_strips or ([0] * len(patches))
    if len(strips) != len(patches):
        fail("pre_build_patch_strips length ({}) must match pre_build_patches length ({})".format(
            len(strips),
            len(patches),
        ))

    exec_runtime = ctx.toolchains[EXEC_TOOLS_TOOLCHAIN_TYPE].exec_tools.exec_runtime
    target_tc = ctx.toolchains[TARGET_TOOLCHAIN_TYPE]
    target_runtime = target_tc.py3_runtime if target_tc else None
    _validate_sdist_toolchains(exec_runtime, target_runtime)

    if not ctx.attr.distribution or not ctx.attr.version:
        parsed_dist, parsed_ver = _parse_sdist_filename(ctx.file.sdist.basename)
    else:
        parsed_dist, parsed_ver = "", ""
    dist = normalize_name(ctx.attr.distribution) if ctx.attr.distribution else parsed_dist
    ver = version.normalize(ctx.attr.version) if ctx.attr.version else parsed_ver

    whldir_name, whl_file_name = _resolve_sdist_output_names(ctx.attr.name)
    out_wheel_dir = ctx.actions.declare_directory(whldir_name)
    out_wheel_file = ctx.actions.declare_file(whl_file_name)

    build_deps = _collect_deps(ctx.attr.build_deps)
    bootstrap_deps = _collect_deps(ctx.attr._bootstrap_deps)

    args = ctx.actions.args()
    args.add("--sdist", ctx.file.sdist.path)
    args.add("--wheel-dir", out_wheel_dir.path)
    args.add("--out-wheel-file", out_wheel_file.path)
    args.add("--workspace-name", ctx.workspace_name)

    args.add_all(
        build_deps.sources,
        map_each = _dir_only,
        expand_directories = False,
        uniquify = True,
        format_each = "--installed-wheel-dir=%s",
    )
    args.add_all(
        [d.label.workspace_root for d in ctx.attr._bootstrap_deps],
        uniquify = True,
        format_each = "--python-path=%s",
    )
    args.add_all(
        build_deps.imports,
        uniquify = True,
        format_each = "--import-root=%s",
    )
    args.add_all(
        build_deps.venv_symlinks,
        map_each = _venv_symlink_import_root,
        uniquify = True,
        format_each = "--import-root=%s",
    )
    args.add_all(
        build_deps.files,
        map_each = _non_dir_dep_file,
        expand_directories = False,
        uniquify = True,
        format_each = "--dep-file=%s",
    )

    if target_runtime and target_runtime.interpreter_version_info:
        tvi = target_runtime.interpreter_version_info
        if tvi.major and tvi.minor != None:
            args.add("--target-python-version", "{}.{}".format(tvi.major, tvi.minor))

    for constraint_target, spec in ctx.attr._platform_constraints.items():
        if ctx.target_platform_has_constraint(constraint_target[platform_common.ConstraintValueInfo]):
            kind, _, val = spec.partition("=")
            args.add("--target-" + kind, val)

    if ctx.attr.add_libdir_to_library_search_path:
        args.add("--add-libdir-to-library-search-path")

    for k, v in sorted(ctx.attr.config_settings.items()):
        args.add("--config-setting={}={}".format(k, v))
    for k, vals in sorted(ctx.attr.config_settings_list.items()):
        for v in vals:
            args.add("--config-setting={}={}".format(k, v))
    for k, v in sorted(ctx.attr.environment.items()):
        args.add("--env={}={}".format(k, v))

    for patch_file, strip_val in zip(patches, strips):
        args.add("--patch", "{}:{}".format(patch_file.path, strip_val))

    helper_files = (
        ctx.files._sdist_wheel_builder_helpers if PyInterpreterProgramInfo in ctx.attr.builder else []
    )
    action_env = (
        {
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONPATH": helper_files[0].dirname,
        } if helper_files else {}
    )
    inputs = depset(
        direct = [ctx.file.sdist] + patches + helper_files,
        transitive = [build_deps.files, bootstrap_deps.files],
    )

    actions_run(
        ctx,
        executable = ctx.attr.builder,
        arguments = [args],
        env = action_env,
        inputs = inputs,
        outputs = [out_wheel_dir, out_wheel_file],
        mnemonic = "PySdistWheelBuild",
        progress_message = "Building wheel from sdist {} into %{{output}}".format(ctx.file.sdist.basename),
        use_default_shell_env = True,
    )

    return [
        DefaultInfo(
            files = depset([out_wheel_file]),
            runfiles = ctx.runfiles(files = [out_wheel_file]),
        ),
        OutputGroupInfo(
            whl = depset([out_wheel_file]),
            whldir = depset([out_wheel_dir]),
        ),
        PyBuiltWheelInfo(
            directory = out_wheel_dir,
            distribution = dist,
            version = ver,
        ),
    ]

py_sdist_wheel = ruleb.Rule(
    implementation = _py_sdist_wheel_impl,
    doc = """
Builds a Python wheel (`.whl`) from an sdist archive in a Bazel build action.

Produces both:
- A default output `File` (`<stem>.sdist_build.whl`): contents are the built wheel;
  the filename is not a valid wheel filename — use `:whldir` (or
  `OutputGroupInfo.whldir` / `PyBuiltWheelInfo.directory`) for the real one.
- A `.whldir` directory artifact (`TreeArtifact`) containing the built wheel with its
  canonical PEP 427 filename.

:::{note}
The default builder uses the host system toolchain (`use_default_shell_env`)
and only supports building wheels compatible with the host platform.
:::

:::{versionadded} VERSION_NEXT_FEATURE
:::
""",
    exec_groups = dict(REQUIRED_EXEC_GROUP_BUILDERS),
    attrs = PY_SDIST_WHEEL_ATTRS,
    provides = [PyBuiltWheelInfo],
    toolchains = [
        ruleb.ToolchainType(TARGET_TOOLCHAIN_TYPE, mandatory = False),
        ruleb.ToolchainType(EXEC_TOOLS_TOOLCHAIN_TYPE, mandatory = True),
    ],
).build()
