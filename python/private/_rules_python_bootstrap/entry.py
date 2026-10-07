"""Entry adapters joining application preparation, storage, and launch."""

import hashlib
import json
import os
import shlex
import zipfile
from dataclasses import replace

from .environment import prepare_venv, resolve_runtime, venv_layout_identity
from .model import Application, PreparedApplication, invocation
from .process import Cancellation, execute
from .storage import Workspace, complete_image, extract_archive, publish_image


def _python_options(application):
    extra = os.environ.pop("RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS", "")
    return list(application.interpreter_args) + shlex.split(extra)


def _read_application(path):
    with open(path, "rb") as source:
        return Application.read(source.read())


def _cache_path(metadata, runtime=None, runfiles=None):
    root = os.environ.get("RULES_PYTHON_EXTRACT_ROOT")
    if not root or not metadata["cache"]:
        return None
    identity = metadata["identity"]
    if runtime is not None:
        identity += "-" + runtime.identity(runfiles)
    name = metadata["name"]
    if os.name == "nt":
        name = os.path.basename(name)
        identity = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:32]
    return os.path.abspath(os.path.join(root, name, identity))


def _prepared_image(application, image):
    runfiles = os.path.join(image, "runfiles")
    if application.venv is not None:
        executable = os.path.join(runfiles, application.venv.executable)
    else:
        executable = application.interpreter.locate(runfiles)
    if not os.path.isfile(executable) or not os.access(executable, os.X_OK):
        raise RuntimeError("Prepared interpreter not executable: " + executable)
    return PreparedApplication(runfiles, executable)


def _prepare_image(application, image, destination, cancellation, runtime):
    runfiles = os.path.join(image, "runfiles")
    # An application defined entirely in external repositories may have no
    # files in the main workspace. It still needs Bazel's working directory.
    os.makedirs(os.path.join(runfiles, application.workspace), exist_ok=True)
    if application.venv is not None:
        prepare_venv(
            application,
            runfiles,
            os.path.join(runfiles, application.venv.root),
            cancellation,
            runtime=runtime,
            image_owned=True,
            final_runfiles=os.path.join(destination, "runfiles")
            if destination
            else None,
        )
    cancellation.check()
    if destination:
        publish_image(image, destination)
        image = destination
    cancellation.check()
    return _prepared_image(application, image)


def directory_main(
    runfiles,
    spec_path,
    arguments,
    *,
    options=None,
    selected=False,
    temporary_directory=None,
    entry=None,
    cleanup=None,
):
    application = _read_application(os.path.join(runfiles, spec_path))
    if entry is not None:
        application = replace(application, entry=entry)
    if cleanup is not None:
        application = replace(application, cleanup=cleanup)
    options = (
        _python_options(application)
        if options is None
        else options + list(application.interpreter_args)
    )
    with Cancellation() as cancellation, Workspace(
        directory=temporary_directory,
        retain=bool(os.environ.get("RULES_PYTHON_BOOTSTRAP_VERBOSE")),
    ) as workspace:
        venv = application.venv
        if venv is None or not venv.recreate:
            executable = (
                os.path.join(runfiles, venv.executable)
                if venv is not None
                else application.interpreter.locate(runfiles)
            )
        else:
            runtime = (
                resolve_runtime(
                    application.interpreter, runfiles, cancellation, selected=selected
                )
                if application.interpreter.resolve
                else None
            )
            root = os.environ.get("RULES_PYTHON_EXTRACT_ROOT")
            destination = None
            if root:
                with open(os.path.join(runfiles, spec_path), "rb") as source:
                    key = hashlib.sha256(source.read() + os.fsencode(runfiles))
                key.update(venv_layout_identity(application, runfiles))
                if runtime is not None:
                    key.update(runtime.identity().encode("ascii"))
                destination = os.path.abspath(
                    os.path.join(root, venv.root, key.hexdigest())
                )
            if destination and complete_image(destination):
                executable = os.path.join(
                    destination, "venv", os.path.relpath(venv.executable, venv.root)
                )
            else:
                if destination:
                    os.makedirs(os.path.dirname(destination), exist_ok=True)
                    workspace.directory = os.path.dirname(destination)
                image = os.path.join(workspace.allocate(), "image")
                cancellation.check()
                executable = prepare_venv(
                    application,
                    runfiles,
                    os.path.join(image, "venv"),
                    cancellation,
                    runtime=runtime,
                )
                if destination:
                    relative = os.path.relpath(executable, image)
                    publish_image(image, destination)
                    executable = os.path.join(destination, relative)
                    workspace.remove()
        prepared = PreparedApplication(runfiles, executable)
        command = invocation(application, prepared, options, arguments, os.environ)
        return execute(
            command,
            workspace,
            os.path.join(runfiles, application.cleanup),
            cancellation,
        )


def archive_main(
    archive,
    metadata,
    arguments,
    *,
    options=None,
    selected=False,
    temporary_directory=None,
):
    with zipfile.ZipFile(archive) as source:
        application = Application.read(source.read("runfiles/" + metadata["spec"]))
    options = (
        _python_options(application)
        if options is None
        else options + list(application.interpreter_args)
    )
    with Cancellation() as cancellation, Workspace(
        directory=temporary_directory,
        retain=bool(os.environ.get("RULES_PYTHON_BOOTSTRAP_VERBOSE")),
    ) as workspace:
        runtime = None
        if application.interpreter.kind != "runfiles":
            runtime = resolve_runtime(
                application.interpreter, "", cancellation, selected=selected
            )
        destination = _cache_path(metadata, runtime)
        needs_resolution = application.interpreter.resolve and runtime is None
        if destination and not needs_resolution and complete_image(destination):
            prepared = _prepared_image(application, destination)
        else:
            if destination:
                os.makedirs(os.path.dirname(destination), exist_ok=True)
                workspace.directory = os.path.dirname(destination)
            image = os.path.join(workspace.allocate(), "image")
            cancellation.check()
            extract_archive(archive, image, cancellation)
            if application.interpreter.resolve and runtime is None:
                runtime = resolve_runtime(
                    application.interpreter,
                    os.path.join(image, "runfiles"),
                    cancellation,
                )
                destination = _cache_path(
                    metadata, runtime, os.path.join(image, "runfiles")
                )
            if destination and complete_image(destination):
                prepared = _prepared_image(application, destination)
            else:
                prepared = _prepare_image(
                    application, image, destination, cancellation, runtime
                )
            if destination:
                workspace.remove()
        # An archive has no caller-provided runfiles manifest of its own.
        environment = dict(os.environ)
        environment.pop("RUNFILES_MANIFEST_FILE", None)
        command = invocation(
            application,
            prepared,
            options,
            arguments,
            environment,
            temporary_zip=os.path.dirname(prepared.runfiles) if not destination else "",
        )
        return execute(
            command,
            workspace,
            os.path.join(prepared.runfiles, application.cleanup),
            cancellation,
        )


def prepare_archive(workspace, image, *, cached=False):
    """Prepare under shell ownership and emit a six-field data-only result."""
    with open(os.path.join(image, "_rules_python_archive.json")) as source:
        metadata = json.load(source)
    application = _read_application(os.path.join(image, "runfiles", metadata["spec"]))
    with Cancellation() as cancellation:
        runtime = (
            resolve_runtime(
                application.interpreter,
                os.path.join(image, "runfiles"),
                cancellation,
                selected=True,
            )
            if application.interpreter.resolve
            else None
        )
        destination = _cache_path(metadata, runtime, os.path.join(image, "runfiles"))
        if cached:
            if (
                not destination
                or os.path.abspath(image) != destination
                or not complete_image(image)
            ):
                raise RuntimeError("Invalid cached application passed by launcher")
            prepared = _prepared_image(application, image)
        elif destination and complete_image(destination):
            prepared = _prepared_image(application, destination)
        else:
            prepared = _prepare_image(
                application, image, destination, cancellation, runtime
            )
        command = invocation(application, prepared, (), (), os.environ)
        fields = [
            "1",
            command.cwd or "",
            prepared.runfiles,
            prepared.executable,
            os.path.join(prepared.runfiles, application.entry),
            "" if destination else workspace,
        ]
        cancellation.check()
        with open(os.path.join(workspace, "invocation"), "wb") as result:
            for field in fields:
                result.write(os.fsencode(field) + b"\0")
        cancellation.check()


def shell_directory_main(arguments):
    runfiles, spec, entry, cleanup, count = arguments[:5]
    count = int(count)
    return directory_main(
        runfiles,
        spec,
        arguments[5 + count :],
        options=arguments[5 : 5 + count],
        selected=True,
        temporary_directory=os.environ.get("TMPDIR") or "/tmp",
        entry=entry,
        cleanup=cleanup,
    )


def shell_archive_main(archive, metadata, arguments):
    count = int(arguments[0])
    return archive_main(
        archive,
        metadata,
        arguments[1 + count :],
        options=arguments[1 : 1 + count],
        selected=True,
        temporary_directory=os.environ.get("TMPDIR") or "/tmp",
    )
