"""Implementation of the zipapp rules."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_python_internal//:rules_python_config.bzl", rp_config = "config")
load("//python/private:attributes.bzl", "apply_config_settings_attr")
load("//python/private:builders.bzl", "builders")
load("//python/private:common.bzl", "BUILTIN_BUILD_PYTHON_ZIP", "actions_run", "create_windows_exe_launcher", "maybe_builtin_build_python_zip", "maybe_create_repo_mapping", "runfiles_root_path", "target_platform_has_any_constraint")
load("//python/private:common_labels.bzl", "labels")
load("//python/private:py_executable_info.bzl", "PyExecutableInfo")
load("//python/private:py_internal.bzl", "py_internal")
load("//python/private:py_runtime_info.bzl", "PyRuntimeInfo")
load("//python/private:toolchain_types.bzl", "EXEC_TOOLS_TOOLCHAIN_TYPE", "LAUNCHER_MAKER_TOOLCHAIN_TYPE")
load("//python/private:transition_labels.bzl", "TRANSITION_LABELS")

def _is_symlink(f):
    if hasattr(f, "is_symlink"):
        return str(int(f.is_symlink))
    else:
        return "-1"

def _create_zipapp_main_py(ctx, py_runtime, py_executable, stage2_bootstrap, runfiles, explicit_symlinks):
    venv_python_exe = py_executable.venv_python_exe
    if venv_python_exe:
        venv_python_exe_path = runfiles_root_path(ctx, venv_python_exe.short_path)
    else:
        venv_python_exe_path = ""

    if py_runtime.interpreter:
        python_binary_actual_path = runfiles_root_path(ctx, py_runtime.interpreter.short_path)
    else:
        python_binary_actual_path = py_runtime.interpreter_path

    zip_main_py = ctx.actions.declare_file(ctx.label.name + ".zip_main.py")

    args = ctx.actions.args()
    args.add(py_runtime.zip_main_template, format = "--template=%s")
    args.add(zip_main_py, format = "--output=%s")

    args.add(
        "%EXTRACT_DIR%=" + paths.join(
            (ctx.label.repo_name or "_main"),
            ctx.label.package,
            ctx.label.name,
        ),
        format = "--substitution=%s",
    )
    args.add("%python_binary%=" + venv_python_exe_path, format = "--substitution=%s")
    args.add("%python_binary_actual%=" + python_binary_actual_path, format = "--substitution=%s")
    args.add("%stage2_bootstrap%=" + runfiles_root_path(ctx, stage2_bootstrap.short_path), format = "--substitution=%s")
    args.add("%workspace_name%=" + ctx.workspace_name, format = "--substitution=%s")

    hash_files_manifest = ctx.actions.args()
    hash_files_manifest.use_param_file("--hash_files_manifest=%s", use_always = True)
    hash_files_manifest.set_param_file_format("multiline")

    inputs = builders.DepsetBuilder()
    inputs.add(py_runtime.zip_main_template)
    _build_manifest(ctx, hash_files_manifest, runfiles, explicit_symlinks, inputs)

    actions_run(
        ctx,
        executable = ctx.attr._zip_main_maker,
        arguments = [args, hash_files_manifest],
        inputs = inputs.build(),
        outputs = [zip_main_py],
        mnemonic = "PyZipAppCreateMainPy",
        progress_message = "Generating zipapp __main__.py: %{label}",
    )
    return zip_main_py

def _map_zip_empty_filenames(list_paths_cb):
    return ["rf-empty|" + path for path in list_paths_cb().to_list()]

def _map_zip_runfiles(file):
    return "rf-file|" + _is_symlink(file) + "|" + file.short_path + "|" + file.path

def _map_zip_symlinks(entry):
    return "rf-symlink|" + _is_symlink(entry.target_file) + "|" + entry.path + "|" + entry.target_file.path

def _map_zip_root_symlinks(entry):
    return "rf-root-symlink|" + _is_symlink(entry.target_file) + "|" + entry.path + "|" + entry.target_file.path

def _map_explicit_symlinks(entry):
    return "symlink|" + entry.runfiles_path + "|" + entry.link_to_path

def _build_manifest(ctx, manifest, runfiles, explicit_symlinks, inputs):
    manifest.add_all(
        # NOTE: Accessing runfiles.empty_filenames materializes them. A lambda
        # is used to defer that.
        [lambda: runfiles.empty_filenames],
        map_each = _map_zip_empty_filenames,
        allow_closure = True,
    )

    manifest.add_all(runfiles.files, map_each = _map_zip_runfiles)
    manifest.add_all(runfiles.symlinks, map_each = _map_zip_symlinks)
    manifest.add_all(runfiles.root_symlinks, map_each = _map_zip_root_symlinks)
    manifest.add_all(explicit_symlinks, map_each = _map_explicit_symlinks)

    inputs.add(runfiles.files)
    inputs.add([entry.target_file for entry in runfiles.symlinks.to_list()])
    inputs.add([entry.target_file for entry in runfiles.root_symlinks.to_list()])
    for entry in explicit_symlinks.to_list():
        inputs.add(entry.files)

    zip_repo_mapping_manifest = maybe_create_repo_mapping(
        ctx = ctx,
        runfiles = runfiles,
    )
    if zip_repo_mapping_manifest:
        # NOTE: rf-root-symlink is used to make it show up under the runfiles
        # subdirectory within the zip.
        manifest.add(
            zip_repo_mapping_manifest.path,
            format = "rf-root-symlink|0|_repo_mapping|%s",
        )
        inputs.add(zip_repo_mapping_manifest)

def _create_zip(ctx, py_runtime, py_executable, stage2_bootstrap):
    output = ctx.actions.declare_file(ctx.label.name + ".zip")
    manifest = ctx.actions.args()
    manifest.use_param_file("%s", use_always = True)
    manifest.set_param_file_format("multiline")

    runfiles = builders.RunfilesBuilder()

    runfiles.add(py_runtime.files)
    if py_executable.venv_python_exe:
        runfiles.add(py_executable.venv_python_exe)

    if py_executable.venv_interpreter_runfiles:
        runfiles.add(py_executable.venv_interpreter_runfiles)
    runfiles.add(py_executable.app_runfiles)
    runfiles.add(stage2_bootstrap)

    runfiles = runfiles.build(ctx)

    zip_main = _create_zipapp_main_py(
        ctx,
        py_runtime,
        py_executable,
        stage2_bootstrap,
        runfiles,
        py_executable.venv_interpreter_symlinks,
    )
    inputs = builders.DepsetBuilder()
    manifest.add("regular|0|__main__.py|{}".format(zip_main.path))
    inputs.add(zip_main)
    _build_manifest(ctx, manifest, runfiles, py_executable.venv_interpreter_symlinks, inputs)

    zipper_args = ctx.actions.args()
    zipper_args.add(output)
    zipper_args.add(ctx.workspace_name, format = "--workspace-name=%s")
    zipper_args.add(
        str(int(py_internal.get_legacy_external_runfiles(ctx))),
        format = "--legacy-external-runfiles=%s",
    )
    if ctx.attr.compression:
        zipper_args.add(ctx.attr.compression, format = "--compression=%s")
    zipper_args.add("--runfiles-dir=runfiles")

    is_windows = target_platform_has_any_constraint(ctx, ctx.attr._windows_constraints)
    zipper_args.add("\\" if is_windows else "/", format = "--target-platform-pathsep=%s")

    actions_run(
        ctx,
        executable = ctx.attr._zipper,
        arguments = [manifest, zipper_args],
        inputs = inputs.build(),
        outputs = [output],
        mnemonic = "PyZipAppCreateZip",
        progress_message = "Reticulating zipapp archive: %{label} into %{output}",
    )
    return output

def _create_shell_bootstrap(ctx, py_runtime, py_executable, stage2_bootstrap):
    preamble = ctx.actions.declare_file(ctx.label.name + ".preamble.sh")

    bundled_pyexe_path = ""
    external_pyexe_path = ""
    if py_runtime.interpreter_path:
        external_pyexe_path = py_runtime.interpreter_path
    else:
        bundled_pyexe_path = runfiles_root_path(ctx, py_runtime.interpreter.short_path)

    substitutions = {
        "%BUNDLED_PYEXE_PATH%": bundled_pyexe_path,
        "%EXTERNAL_PYEXE_PATH%": external_pyexe_path,
        "%EXTRACT_DIR%": paths.join(
            (ctx.label.repo_name or "_main"),
            ctx.label.package,
            ctx.label.name,
        ),
        "%INTERPRETER_ARGS%": "\n".join([
            '"{}"'.format(v)
            for v in py_executable.interpreter_args
        ]),
        "%STAGE2_BOOTSTRAP%": runfiles_root_path(ctx, stage2_bootstrap.short_path),
    }
    ctx.actions.expand_template(
        template = ctx.file._zip_shell_template,
        output = preamble,
        substitutions = substitutions,
        is_executable = True,
    )
    return preamble

def _create_self_executable_zip(ctx, preamble, zip_file):
    pyz = ctx.actions.declare_file(ctx.label.name + ".pyz")
    args = ctx.actions.args()
    args.add(preamble)
    args.add(zip_file)
    args.add(pyz)
    actions_run(
        ctx,
        executable = ctx.attr._exe_zip_maker,
        arguments = [args],
        inputs = depset([preamble, zip_file]),
        outputs = [pyz],
        mnemonic = "PyZipAppCreateExecutableZip",
        progress_message = "Reticulating zipapp executable: %{label} into %{output}",
    )
    return pyz

def _py_zipapp_executable_impl(ctx):
    py_executable = ctx.attr.binary[PyExecutableInfo]
    py_runtime = ctx.attr.binary[PyRuntimeInfo]

    stage2_bootstrap = py_executable.stage2_bootstrap

    zip_file = _create_zip(ctx, py_runtime, py_executable, stage2_bootstrap)
    if ctx.attr.executable:
        if target_platform_has_any_constraint(ctx, ctx.attr._windows_constraints):
            executable = ctx.actions.declare_file(ctx.label.name + ".exe")

            # The zipapp is an opaque zip file, so the Bazel Python launcher doesn't
            # know how to look inside it to find the Python interpreter. This means
            # we can only use system paths or programs on PATH to bootstrap.
            if py_runtime.interpreter_path:
                bootstrap_python_path = py_runtime.interpreter_path
            else:
                # A special value the Bazel Python launcher recognized to skip
                # lookup in the runfiles and uses `python.exe` from PATH.
                bootstrap_python_path = "python"

            create_windows_exe_launcher(
                ctx,
                output = executable,
                # The path to a python to use to invoke e.g. `python.exe foo.zip`
                python_binary_path = bootstrap_python_path,
                # Tell the launcher to invoke `python_binary_path` on itself
                # after removing its file extension and appending `.zip`.
                use_zip_file = True,
            )
            default_outputs = [executable, zip_file]
        else:
            preamble = _create_shell_bootstrap(ctx, py_runtime, py_executable, stage2_bootstrap)
            executable = _create_self_executable_zip(ctx, preamble, zip_file)
            default_outputs = [executable]
    else:
        # Bazel requires executable=True rules to have an executable given, so give
        # a fake one to satisfy that.
        default_outputs = [zip_file]
        executable = ctx.actions.declare_file(ctx.label.name + "-not-executable")
        ctx.actions.write(executable, "echo 'ERROR: Non executable zip file'; exit 1")

    return [
        DefaultInfo(
            files = depset(default_outputs),
            runfiles = ctx.runfiles(files = default_outputs),
            executable = executable,
        ),
        OutputGroupInfo(
            python_zip_file = depset([zip_file]),
        ),
    ]

def _transition_zipapp_impl(settings, attr):
    settings = apply_config_settings_attr(dict(settings), attr)

    # Force this to false, otherwise the binary is already a zipapp
    settings[labels.BUILD_PYTHON_ZIP] = False
    maybe_builtin_build_python_zip("false", settings)
    return settings

_zipapp_transition = transition(
    implementation = _transition_zipapp_impl,
    inputs = TRANSITION_LABELS,
    outputs = TRANSITION_LABELS + [
        labels.BUILD_PYTHON_ZIP,
    ] + BUILTIN_BUILD_PYTHON_ZIP,
)

_ATTRS = {
    "binary": attr.label(
        doc = """
A `py_binary` or `py_test` (or equivalent) target to package.
""",
        providers = [PyExecutableInfo, PyRuntimeInfo],
        mandatory = True,
    ),
    "compression": attr.string(
        doc = """
The compression level to use.

Typically 0 to 9, with higher numbers being to compress more.
""",
        default = "",
    ),
    "config_settings": attr.label_keyed_string_dict(
        doc = """
Config settings to change for this target.

The keys are labels for settings, and the values are strings for the new value
to use. Pass `Label` objects or canonical label strings for the keys to ensure
they resolve as expected (canonical labels start with `@@` and can be
obtained by calling `str(Label(...))`).

Most `@rules_python//python/config_setting` settings can be used here, which
allows, for example, making only a certain `py_binary` use
{obj}`--bootstrap_impl=script`.

Additional or custom config settings can be registered using the
{obj}`add_transition_setting` API. This allows, for example, forcing a
particular CPU, or defining a custom setting that `select()` uses elsewhere
to pick between `pip.parse` hubs. See the [How to guide on multiple
versions of a library] for a more concrete example.

:::{note}
These values are transitioned on, so will affect the analysis graph and the
associated memory overhead. The more unique configurations in your overall
build, the more memory and (often unnecessary) re-analysis and re-building
can occur. See
https://bazel.build/extending/config#memory-performance-considerations for
more information about risks and considerations.
:::
""",
    ),
    "executable": attr.bool(
        doc = """
Whether the output should be an executable zip file.
""",
        default = True,
    ),
    # Required to opt-in to the transition feature.
    "_allowlist_function_transition": attr.label(
        default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
    ),
    "_exe_zip_maker": attr.label(
        cfg = "exec",
        default = "//tools/private/zipapp:exe_zip_maker",
    ),
    "_launcher": attr.label(
        cfg = "target",
        # NOTE: This is an executable, but is only used for Windows. It
        # can't have executable=True because the backing target is an
        # empty target for other platforms.
        default = "//tools/launcher:launcher",
    ),
    "_windows_constraints": attr.label_list(
        default = [
            "@platforms//os:windows",
        ],
    ),
    "_zip_main_maker": attr.label(
        cfg = "exec",
        default = "//tools/private/zipapp:zip_main_maker",
    ),
    "_zip_shell_template": attr.label(
        default = ":zip_shell_template",
        allow_single_file = True,
    ),
    "_zipper": attr.label(
        cfg = "exec",
        default = "//tools/private/zipapp:zipper",
    ),
} | ({
    "_windows_launcher_maker": attr.label(
        default = "@bazel_tools//tools/launcher:launcher_maker",
        cfg = "exec",
        executable = True,
    ),
} if not rp_config.bazel_9_or_later else {})

_TOOLCHAINS = [EXEC_TOOLS_TOOLCHAIN_TYPE] + ([LAUNCHER_MAKER_TOOLCHAIN_TYPE] if rp_config.bazel_9_or_later else [])

_COMMON_RULE_DOC = """

Output groups:

* `python_zip_file`: (*deprecated*) The plain, non-self-executable zipapp zipfile.
  *This output group is deprecated and retained for compatibility with
  the previous implicit zipapp functionality. Set `executable=False`
  and use the default output of the target instead.*

:::{versionadded} 1.9.0
:::
""".lstrip()

py_zipapp_binary = rule(
    doc = """
Packages a `py_binary` as a Python zipapp.

{}
""".format(_COMMON_RULE_DOC),
    implementation = _py_zipapp_executable_impl,
    attrs = _ATTRS,
    # NOTE: While this is marked executable, it is conditionally executable
    # based on the `executable` attribute.
    executable = True,
    toolchains = _TOOLCHAINS,
    cfg = _zipapp_transition,
)

py_zipapp_test = rule(
    doc = """
Packages a `py_test` as a Python zipapp.

This target is also a valid test target to run.

{}
""".format(_COMMON_RULE_DOC),
    implementation = _py_zipapp_executable_impl,
    attrs = _ATTRS,
    # NOTE: While this is marked as a test, it is conditionally executable
    # based on the `executable` attribute.
    test = True,
    toolchains = _TOOLCHAINS,
    cfg = _zipapp_transition,
)
