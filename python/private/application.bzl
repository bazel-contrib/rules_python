"""Build an application once, then expose it as a directory or archive."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load(":builders.bzl", "builders")
load(":common.bzl", "ExplicitSymlink", "actions_run", "is_windows_platform", "maybe_create_repo_mapping", "runfiles_root_path")
load(":py_application_info.bzl", "PyApplicationInfo")
load(":py_internal.bzl", "py_internal")

APPLICATION_ATTRS = {
    "_application_default_python": attr.label(default = Label("//python/private:python_bootstrap_template.txt"), allow_single_file = True),
    "_application_default_shell": attr.label(default = Label("//python/private:stage1_bootstrap_template"), allow_single_file = True),
    "_application_default_zip": attr.label(default = Label("//python/private/zipapp:zip_main_template"), allow_single_file = True),
    "_application_driver": attr.label(default = Label("//python/private:_rules_python_bootstrap/driver.py"), allow_single_file = True),
    "_application_python": attr.label(default = Label("//python/private:application_python_template.txt"), allow_single_file = True),
    "_application_shell": attr.label(default = Label("//python/private:application_shell_template.sh"), allow_single_file = True),
    "_application_sources": attr.label(default = Label("//python/private:application_sources")),
    "_application_zip": attr.label(default = Label("//python/private:application_zip_template.txt"), allow_single_file = True),
    "_application_zip_main_maker": attr.label(default = Label("//tools/zipapp:zip_main_maker"), cfg = "exec"),
    "_application_zipper": attr.label(default = Label("//tools/zipapp:zipper"), cfg = "exec"),
}

def _link_record(link):
    return json.encode([link.venv_path, link.link_to_path])

def create_application(ctx, *, runtime, stage2, venv, runfiles, interpreter_args):
    """Declare the common image and launch specification from executable inputs.

    Args:
        ctx: Rule context.
        runtime: Selected PyRuntimeInfo.
        stage2: Selected application entry File.
        venv: Executable-owned virtual environment layout.
        runfiles: Application and runtime runfiles without the outer executable.
        interpreter_args: Arguments bound to the target interpreter.

    Returns:
        The private PyApplicationInfo consumed by launchers and packaging.
    """
    spec = ctx.actions.declare_file(ctx.label.name + ".application.json")
    link_file = ctx.actions.declare_file(ctx.label.name + ".application_links.jsonl")
    links = depset(transitive = [venv.interpreter_symlinks, venv.lib_symlinks])
    content = ctx.actions.args()
    content.set_param_file_format("multiline")
    content.add_all(links, map_each = _link_record)
    ctx.actions.write(link_file, content)
    actual = venv.interpreter_actual_path
    settings = {
        "cleanup": runfiles_root_path(ctx, ctx.file._bootstrap_cleanup.short_path),
        "entry": runfiles_root_path(ctx, stage2.short_path),
        "interpreter": {
            "kind": "runfiles" if runtime.interpreter else ("absolute" if paths.is_absolute(actual) else "path"),
            "path": actual,
            "resolve": not runtime.supports_build_time_venv,
        },
        "interpreter_args": interpreter_args,
        "venv": {
            "executable": runfiles_root_path(ctx, venv.interpreter.short_path),
            "links": runfiles_root_path(ctx, link_file.short_path),
            "recreate": venv.recreate_venv_at_runtime,
            "root": venv.venv_root,
            "site_packages": venv.venv_site_packages,
        } if venv.interpreter else None,
        "version": 1,
        "workspace": ctx.workspace_name,
    }
    ctx.actions.write(spec, json.encode(settings))
    image_runfiles = runfiles.merge_all([
        ctx.runfiles([spec, link_file, stage2, ctx.file._bootstrap_cleanup] + ctx.files._application_sources),
        ctx.runfiles(venv.files_without_interpreter),
        venv.lib_runfiles,
        venv.interpreter_runfiles,
    ])
    interpreter_links = []
    if venv.interpreter and runtime.interpreter:
        interpreter_links.append(ExplicitSymlink(
            runfiles_path = settings["venv"]["executable"],
            venv_path = paths.relativize(settings["venv"]["executable"], venv.venv_root),
            link_to_path = actual,
            files = depset([runtime.interpreter]),
        ))
    return PyApplicationInfo(
        spec = spec,
        settings = settings,
        runfiles = image_runfiles,
        symlinks = depset(interpreter_links, transitive = [links]),
    )

def is_default_bootstrap(ctx, template):
    return template in (ctx.file._application_default_python, ctx.file._application_default_shell)

def create_application_launcher(ctx, *, application, output, shell_entry, archive = False, cache = False, shebang = "#!/usr/bin/env python3"):
    """Generate a thin entry adapter from the same application specification.

    Args:
        ctx: Rule context.
        application: Private application image provider.
        output: Launcher File to write.
        shell_entry: Whether the adapter starts in Bash instead of Python.
        archive: Whether the shell adapter has an appended archive.
        cache: Whether archive preparation permits a persistent extract root.
        shebang: Interpreter directive for a Python adapter.
    """
    settings = application.settings
    venv = settings["venv"]
    interpreter = settings["interpreter"]
    subs = {
        "%application_spec%": repr(runfiles_root_path(ctx, application.spec.short_path)),
        "%archive%": "1" if archive else "0",
        "%bootstrap_parent%": repr(paths.dirname(paths.dirname(runfiles_root_path(ctx, ctx.file._application_driver.short_path)))),
        "%cache%": "1" if cache else "0",
        "%cache_name%": shell.quote(paths.join(ctx.label.repo_name or "_main", ctx.label.package, ctx.label.name)),
        "%cleanup_shell%": shell.quote(settings["cleanup"]),
        "%driver_shell%": shell.quote(runfiles_root_path(ctx, ctx.file._application_driver.short_path)),
        "%entry%": repr(settings["entry"]),
        "%entry_shell%": shell.quote(settings["entry"]),
        "%interpreter_args_shell%": "\n".join([shell.quote(arg) for arg in settings["interpreter_args"]]),
        "%interpreter_kind%": shell.quote(interpreter["kind"]),
        "%interpreter_shell%": shell.quote(interpreter["path"]),
        "%recreate%": "1" if venv and venv["recreate"] else "0",
        "%resolve%": "1" if interpreter["resolve"] else "0",
        "%shebang%": shebang,
        "%spec_shell%": shell.quote(runfiles_root_path(ctx, application.spec.short_path)),
        "%venv_executable_shell%": shell.quote(venv["executable"] if venv else ""),
        "%workspace_shell%": shell.quote(settings["workspace"]),
    }
    ctx.actions.expand_template(
        template = ctx.file._application_shell if shell_entry else ctx.file._application_python,
        output = output,
        substitutions = subs,
        is_executable = True,
    )

def _is_symlink(file):
    return str(int(file.is_symlink)) if hasattr(file, "is_symlink") else "-1"

def _empty_files(callback):
    return ["rf-empty|" + path for path in callback().to_list()]

def _runfile(file):
    return "rf-file|" + _is_symlink(file) + "|" + file.short_path + "|" + file.path

def _symlink(entry):
    return "rf-symlink|" + _is_symlink(entry.target_file) + "|" + entry.path + "|" + entry.target_file.path

def _root_symlink(entry):
    return "rf-root-symlink|" + _is_symlink(entry.target_file) + "|" + entry.path + "|" + entry.target_file.path

def _explicit_symlink(entry):
    return "symlink|" + entry.runfiles_path + "|" + entry.link_to_path

def _manifest(ctx, manifest, application, inputs):
    runfiles = application.runfiles
    manifest.add_all([lambda: runfiles.empty_filenames], map_each = _empty_files, allow_closure = True)
    manifest.add_all(runfiles.files, map_each = _runfile)
    manifest.add_all(runfiles.symlinks, map_each = _symlink)
    manifest.add_all(runfiles.root_symlinks, map_each = _root_symlink)
    manifest.add_all(application.symlinks, map_each = _explicit_symlink)
    inputs.add(runfiles.files)
    inputs.add([entry.target_file for entry in runfiles.symlinks.to_list()])
    inputs.add([entry.target_file for entry in runfiles.root_symlinks.to_list()])
    for entry in application.symlinks.to_list():
        inputs.add(entry.files)
    mapping = maybe_create_repo_mapping(ctx = ctx, runfiles = runfiles)
    if mapping:
        manifest.add(mapping.path, format = "rf-root-symlink|0|_repo_mapping|%s")
        inputs.add(mapping)

def create_application_archive(ctx, *, application, output, template, cache, compression = ""):
    """Package the executable's declared application image without rebuilding it.

    Args:
        ctx: Rule context.
        application: Private application image provider from the binary.
        output: Archive File to write.
        template: Runtime-selected ZIP main template, including custom templates.
        cache: Whether the archive permits persistent preparation.
        compression: Optional zipper compression level.
    """
    main = ctx.actions.declare_file(output.basename + ".main.py", sibling = output)
    metadata_file = ctx.actions.declare_file(output.basename + ".metadata.json", sibling = output)
    modern = template == ctx.file._application_default_zip
    template = ctx.file._application_zip if modern else template
    settings = application.settings
    metadata = {
        "cache": cache,
        "name": paths.join(ctx.label.repo_name or "_main", ctx.label.package, ctx.label.name),
        "spec": runfiles_root_path(ctx, application.spec.short_path),
        "version": 1,
    }
    substitutions = {
        "%EXTRACT_DIR%": metadata["name"],
        "%bootstrap_parent%": repr(paths.dirname(paths.dirname(runfiles_root_path(ctx, ctx.file._application_driver.short_path)))),
        "%python_binary%": settings["venv"]["executable"] if settings["venv"] else "",
        "%python_binary_actual%": settings["interpreter"]["path"],
        "%stage2_bootstrap%": settings["entry"],
        "%workspace_name%": settings["workspace"],
    }
    args = ctx.actions.args()
    args.add(template, format = "--template=%s")
    args.add(main, format = "--output=%s")
    args.add(metadata_file, format = "--metadata-output=%s")
    args.add(json.encode(metadata), format = "--metadata=%s")
    for key, value in substitutions.items():
        args.add(key + "=" + value, format = "--substitution=%s")
    hash_manifest = ctx.actions.args()
    hash_manifest.use_param_file("--hash_files_manifest=%s", use_always = True)
    hash_manifest.set_param_file_format("multiline")
    inputs = builders.DepsetBuilder()
    inputs.add(template)
    _manifest(ctx, hash_manifest, application, inputs)
    actions_run(
        ctx,
        executable = ctx.attr._application_zip_main_maker,
        arguments = [args, hash_manifest],
        inputs = inputs.build(),
        outputs = [main, metadata_file],
        mnemonic = "PyApplicationArchiveMain",
        progress_message = "Preparing application archive: %{label}",
    )
    manifest = ctx.actions.args()
    manifest.use_param_file("%s", use_always = True)
    manifest.set_param_file_format("multiline")
    manifest.add("regular|0|__main__.py|" + main.path)
    manifest.add("regular|0|_rules_python_archive.json|" + metadata_file.path)
    zip_inputs = builders.DepsetBuilder()
    zip_inputs.add([main, metadata_file])
    _manifest(ctx, manifest, application, zip_inputs)
    zip_args = ctx.actions.args()
    zip_args.add(output)
    zip_args.add(ctx.workspace_name, format = "--workspace-name=%s")
    zip_args.add(str(int(py_internal.get_legacy_external_runfiles(ctx))), format = "--legacy-external-runfiles=%s")
    zip_args.add("--runfiles-dir=runfiles")
    zip_args.add("\\" if is_windows_platform(ctx) else "/", format = "--target-platform-pathsep=%s")
    if compression:
        zip_args.add(compression, format = "--compression=%s")
    actions_run(
        ctx,
        executable = ctx.attr._application_zipper,
        arguments = [manifest, zip_args],
        inputs = zip_inputs.build(),
        outputs = [output],
        mnemonic = "PyApplicationArchive",
        progress_message = "Packaging application image: %{label}",
    )
