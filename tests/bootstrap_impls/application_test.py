"""Behavior at the application model's storage, preparation and launch boundaries."""

import errno
import json
import ntpath
import os
import signal
import stat
import subprocess
import sys
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import pytest

from python.private._rules_python_bootstrap import (
    entry,
    environment,
    model,
    process,
    storage,
)
from python.runfiles import runfiles


@pytest.fixture(name="application")
def fixture_application(tmp_path):
    root = tmp_path / "runfiles"
    source = root / "app.venv"
    (source / "bin").mkdir(parents=True)
    (source / "lib/site-packages").mkdir(parents=True)
    (source / "pyvenv.cfg").touch()
    (root / "links.jsonl").write_text("")
    (root / "entry.py").write_text("pass\n")
    value = model.Application(
        entry="entry.py",
        workspace="_main",
        interpreter=model.Interpreter("absolute", sys.executable, False),
        interpreter_args=(),
        cleanup="cleanup.py",
        venv=model.Venv(
            "app.venv", "app.venv/bin/python", "lib/site-packages", True, "links.jsonl"
        ),
    )
    return value, root


def test_preparation_failure_removes_only_owned_workspace(tmp_path):
    (tmp_path / "caller").touch()
    with pytest.raises(ValueError, match="setup failed"):
        with storage.Workspace(directory=tmp_path) as workspace:
            owned = Path(workspace.allocate())
            (owned / "partial").touch()
            assert workspace.allocate() == str(owned)
            raise ValueError("setup failed")
    assert not owned.exists()
    assert [path.name for path in tmp_path.iterdir()] == ["caller"]


def test_verbose_retention_releases_ownership(tmp_path):
    with storage.Workspace(directory=tmp_path, retain=True) as workspace:
        owned = Path(workspace.allocate())
        workspace.remove()
        assert workspace.path is None
    assert owned.is_dir()


def test_rollback_removes_readonly_files_without_changing_link_targets(tmp_path):
    caller = tmp_path / "caller"
    caller.write_text("keep")
    caller.chmod(0o444)
    before = caller.stat().st_mode
    try:
        with storage.Workspace(directory=tmp_path) as workspace:
            owned = Path(workspace.allocate())
            readonly = owned / "readonly"
            readonly.write_text("remove")
            readonly.chmod(0o444)
            (owned / "borrowed").symlink_to(caller)
        assert not owned.exists()
        assert caller.stat().st_mode == before
        assert caller.read_text() == "keep"
    finally:
        caller.chmod(0o644)


@pytest.mark.parametrize("existing", ["empty", "partial", "complete"])
def test_publication_preserves_existing_destination(tmp_path, existing):
    staging, destination = tmp_path / "staging", tmp_path / "destination"
    staging.mkdir()
    (staging / "new").touch()
    destination.mkdir()
    if existing != "empty":
        (destination / "caller").write_text("keep")
    if existing == "complete":
        (destination / storage.COMPLETION_FILE).touch()
        storage.publish_image(staging, destination)
        assert not staging.exists()
    else:
        with pytest.raises(RuntimeError, match="Incomplete Python runtime"):
            storage.publish_image(staging, destination)
        assert staging.exists()
    assert not (destination / "new").exists()
    if existing != "empty":
        assert (destination / "caller").read_text() == "keep"


def test_published_image_survives_workspace_rollback(tmp_path):
    destination = tmp_path / "cache"
    with storage.Workspace(directory=tmp_path) as workspace:
        image = Path(workspace.allocate()) / "image"
        image.mkdir()
        (image / "payload").write_text("complete")
        storage.publish_image(image, destination)
    assert storage.complete_image(destination)
    assert (destination / "payload").read_text() == "complete"
    assert destination.is_symlink()
    assert not os.path.isabs(os.readlink(destination))
    backing = destination.resolve().parent
    assert set(tmp_path.iterdir()) == {destination, backing}
    probe = tmp_path / "permissions"
    probe.mkdir()
    assert stat.S_IMODE(backing.stat().st_mode) == stat.S_IMODE(probe.stat().st_mode)


@pytest.mark.parametrize("collision", ["empty", "symlink", "complete"])
def test_publication_collision_never_replaces_caller_entry(
    tmp_path, monkeypatch, collision
):
    destination = tmp_path / "cache"
    caller = tmp_path / "caller"
    caller.mkdir()
    (caller / "keep").write_text("untouched")
    original = os.symlink

    def concurrent_entry(target, path, **kwargs):
        if collision == "symlink":
            original("missing-caller-target", path, target_is_directory=True)
        else:
            destination.mkdir()
            if collision == "complete":
                (destination / storage.COMPLETION_FILE).touch()
                (destination / "winner").write_text("complete")
        return original(target, path, **kwargs)

    monkeypatch.setattr(os, "symlink", concurrent_entry)
    with storage.Workspace(directory=tmp_path) as workspace:
        image = Path(workspace.allocate()) / "image"
        image.mkdir()
        (image / "loser").touch()
        if collision == "complete":
            storage.publish_image(image, destination)
            assert (destination / "winner").read_text() == "complete"
        else:
            with pytest.raises(RuntimeError, match="Incomplete Python runtime"):
                storage.publish_image(image, destination)
    assert set(tmp_path.iterdir()) == {caller, destination}
    assert (caller / "keep").read_text() == "untouched"
    assert not (destination / "loser").exists()
    if collision == "symlink":
        assert os.readlink(destination) == "missing-caller-target"
    elif collision == "empty":
        assert not list(destination.iterdir())


def test_failed_publication_rolls_back_only_unpublished_backing(tmp_path, monkeypatch):
    caller = tmp_path / "keep"
    caller.write_text("untouched")

    def denied(*_args, **_kwargs):
        raise OSError(errno.EACCES, "publication denied")

    monkeypatch.setattr(os, "symlink", denied)
    with pytest.raises(OSError, match="publication denied"):
        with storage.Workspace(directory=tmp_path) as workspace:
            image = Path(workspace.allocate()) / "image"
            image.mkdir()
            storage.publish_image(image, tmp_path / "cache")
    assert list(tmp_path.iterdir()) == [caller]
    assert caller.read_text() == "untouched"


@pytest.mark.parametrize("after_publish", ["error", "cancellation"])
def test_visible_image_survives_publication_interruption(
    tmp_path, monkeypatch, after_publish
):
    original = os.symlink
    destination = tmp_path / "cache"
    with process.Cancellation() as cancellation, storage.Workspace(
        directory=tmp_path
    ) as workspace:

        def interrupted(*args, **kwargs):
            original(*args, **kwargs)
            if after_publish == "error":
                raise OSError(errno.EIO, "publication reply lost")
            signal.raise_signal(signal.SIGINT)

        monkeypatch.setattr(os, "symlink", interrupted)
        image = Path(workspace.allocate()) / "image"
        image.mkdir()
        (image / "payload").write_text("complete")
        storage.publish_image(image, destination)
        if after_publish == "cancellation":
            with pytest.raises(process.Cancelled):
                cancellation.check()
    assert storage.complete_image(destination)
    assert (destination / "payload").read_text() == "complete"
    assert set(tmp_path.iterdir()) == {destination, destination.resolve().parent}


def test_external_only_image_preserves_main_workspace_directory(application, tmp_path):
    app, _ = application
    app = replace(app, entry="external/main.py", venv=None)
    image = tmp_path / "image"
    runfiles_root = image / "runfiles"
    (runfiles_root / "external").mkdir(parents=True)
    (runfiles_root / "external/main.py").write_text("pass\n")
    cache = tmp_path / "published"
    with process.Cancellation() as cancellation:
        prepared = entry._prepare_image(app, str(image), str(cache), cancellation, None)
    command = model.invocation(app, prepared, (), (), {"RUN_UNDER_RUNFILES": "1"})
    assert command.cwd is not None
    assert command.cwd == str(cache / "runfiles/_main")
    assert Path(command.cwd).is_dir()
    assert storage.complete_image(cache)


def test_windows_child_registration_cancellation_reaps_before_removal(
    tmp_path, monkeypatch
):
    # Real process ownership, with Windows dispatch selected independently of
    # the host. Native Windows console delivery is covered by platform tests.
    monkeypatch.setattr(process, "os", SimpleNamespace(name="nt"))
    children = []
    original = subprocess.Popen

    def interrupted_spawn(*args, **kwargs):
        child = original(*args, **kwargs)
        children.append(child)
        signal.raise_signal(signal.SIGINT)
        return child

    monkeypatch.setattr(subprocess, "Popen", interrupted_spawn)
    command = model.Invocation(
        sys.executable,
        (sys.executable, "-c", "import time; time.sleep(60)"),
        dict(os.environ),
        None,
    )
    before = signal.getsignal(signal.SIGINT)
    try:
        with pytest.raises(SystemExit) as error:
            with process.Cancellation() as cancellation, storage.Workspace(
                directory=tmp_path
            ) as workspace:
                owned = Path(workspace.allocate())
                process.execute(command, workspace, "unused", cancellation)
        assert error.value.code == 128 + signal.SIGINT
        assert len(children) == 1 and children[0].poll() is not None
        assert not owned.exists()
        assert signal.getsignal(signal.SIGINT) == before
    finally:
        for child in children:
            if child.poll() is None:
                child.kill()
            child.wait()


@pytest.mark.parametrize(
    "mode,status",
    [
        ("handled", 23),
        ("ignored", 17),
        ("inherited_ignore", 29),
        ("high_bit", 0xC000013A),
    ],
)
def test_native_windows_console_handoff(tmp_path, mode, status):
    if sys.platform != "win32":
        pytest.skip("native Windows console delivery")
    else:
        fixture = runfiles.CreateOrRaise().Rlocation(
            os.environ["WINDOWS_CONSOLE_FIXTURE"]
        )
        assert fixture is not None
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        result = subprocess.run(
            [sys.executable, fixture, "controller", str(tmp_path), mode],
            capture_output=True,
            text=True,
            timeout=30,
            creationflags=subprocess.CREATE_NEW_CONSOLE,
            startupinfo=startup,
            check=False,
        )
        assert result.returncode == status, result.stdout + result.stderr
        assert not Path((tmp_path / "workspace").read_text()).exists()


@pytest.mark.skipif(os.name != "posix", reason="POSIX signal-mask handoff")
def test_exec_transition_detects_signal_during_handler_restoration(monkeypatch):
    original = signal.signal
    with process.Cancellation() as cancellation:
        injected = False

        def restore(signum, disposition):
            nonlocal injected
            previous = original(signum, disposition)
            if not injected:
                injected = True
                # Python handlers can run on the main thread for a signal
                # delivered to another, unblocked thread during this transition.
                cancellation._record(signal.SIGTERM, None)
            return previous

        with monkeypatch.context() as patch:
            patch.setattr(signal, "signal", restore)
            with pytest.raises(process.Cancelled) as error:
                cancellation.prepare_exec()
        assert error.value.signum == signal.SIGTERM
        assert injected


@pytest.mark.skipif(os.name != "posix", reason="POSIX inherited masks")
def test_exec_transition_preserves_inherited_mask():
    if sys.platform == "win32":
        pytest.skip("POSIX inherited masks")
    else:
        original = signal.pthread_sigmask(signal.SIG_BLOCK, [signal.SIGHUP])
        try:
            expected = signal.pthread_sigmask(signal.SIG_BLOCK, [])
            with process.Cancellation() as cancellation:
                cancellation.prepare_exec()
                assert signal.pthread_sigmask(signal.SIG_BLOCK, []) == expected
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, original)


def test_runfiles_wrapper_can_resolve_external_interpreter(application, tmp_path):
    app, root = application
    # Declared as runfiles, but the wrapper resolves to an external executable.
    # Publication must not turn that absolute reference into a relative link.
    app = replace(app, interpreter=model.Interpreter("runfiles", "wrapper", True))
    runtime = environment.current_runtime()
    destination = root / app.venv.root
    with process.Cancellation() as cancellation:
        executable = environment.prepare_venv(
            app,
            str(root),
            str(destination),
            cancellation,
            runtime=runtime,
            image_owned=True,
        )
    assert os.path.isabs(os.readlink(executable))
    assert Path(executable).resolve() == Path(sys.executable).resolve()


def test_overlay_includes_explicit_links_without_source_directories(
    application, tmp_path
):
    app, root = application
    payload = root / "header.h"
    payload.write_text("header")
    (root / app.venv.links).write_text(
        json.dumps(["include/package/header.h", "header.h"]) + "\n"
    )
    destination = tmp_path / "prepared"
    with process.Cancellation() as cancellation:
        environment.prepare_venv(app, str(root), str(destination), cancellation)
    assert (destination / "include/package/header.h").read_text() == "header"
    assert (destination / "lib/site-packages").is_symlink()


def test_preparation_does_not_enumerate_dependency_tree(
    application, tmp_path, monkeypatch
):
    app, root = application
    dependencies = root / app.venv.root / app.venv.site_packages
    nested = dependencies / "package/nested"
    nested.mkdir(parents=True)
    (nested / "module.py").write_text("VALUE = 42\n")
    original_listdir = os.listdir

    def listdir(path):
        assert not Path(path).is_relative_to(dependencies), (
            "walked application dependencies"
        )
        return original_listdir(path)

    monkeypatch.setattr(os, "listdir", listdir)
    destination = tmp_path / "prepared"
    with process.Cancellation() as cancellation:
        environment.venv_layout_identity(app, str(root))
        environment.prepare_venv(app, str(root), str(destination), cancellation)
    assert (
        destination / app.venv.site_packages / "package/nested/module.py"
    ).read_text() == "VALUE = 42\n"


@pytest.mark.parametrize("change", ["links", "bin", "data", "implementation"])
def test_directory_cache_tracks_preparation_inputs(
    application, monkeypatch, tmp_path, change
):
    app, root = application
    implementation = tmp_path / "implementation"
    implementation.mkdir()
    for name in (
        "diagnostics.py",
        "environment.py",
        "entry.py",
        "model.py",
        "process.py",
        "storage.py",
    ):
        (implementation / name).write_text("initial")
    monkeypatch.setattr(environment, "__file__", str(implementation / "environment.py"))
    original = environment.venv_layout_identity(app, str(root))
    assert environment.venv_layout_identity(app, str(root)) == original
    if change == "links":
        (root / app.venv.links).write_text(
            json.dumps(["include/header.h", "header.h"]) + "\n"
        )
    elif change == "bin":
        (root / app.venv.root / "bin/new-tool").touch()
    elif change == "data":
        (root / app.venv.root / "share").mkdir()
    else:
        (implementation / "environment.py").write_text("changed")
    assert environment.venv_layout_identity(app, str(root)) != original


def test_runtime_identity_ignores_image_staging_path(tmp_path):
    root1, root2 = (
        str(tmp_path / name) for name in ("first/runfiles", "second/runfiles")
    )
    runtime = environment.Runtime(
        root1 + "/python/bin/python",
        root1 + "/python",
        "lib/site-packages",
        (3, 11, 1),
        "",
    )
    relocated = replace(
        runtime, executable=root2 + "/python/bin/python", prefix=root2 + "/python"
    )
    assert runtime.identity(root1) == relocated.identity(root2)
    assert runtime.identity(root1) != replace(runtime, version=(3, 12, 0)).identity(
        root1
    )


def test_image_containment_accepts_external_windows_drive(monkeypatch):
    monkeypatch.setattr(environment, "os", SimpleNamespace(path=ntpath))
    assert environment._inside(r"D:\runtime\bin\python.exe", r"D:\runtime")
    assert not environment._inside(r"C:\Python\python.exe", r"D:\runtime")
    assert not environment._inside(r"D:\runtime-other\python.exe", r"D:\runtime")


def test_invocation_keeps_preparation_state_out_of_application_environment(application):
    app, root = application
    inherited = {
        "PYTHONSAFEPATH": "",
        "RUN_UNDER_RUNFILES": "1",
        "RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS": "-Xagain",
        "__PYVENV_LAUNCHER__": "wrong",
        "RUNFILES_MANIFEST_FILE": "unrelated",
    }
    prepared = model.PreparedApplication(str(root), sys.executable)
    command = model.invocation(
        app,
        prepared,
        ["-m", "debugpy"],
        ["argument with spaces"],
        inherited,
        temporary_zip=str(root.parent),
    )
    assert command.argv == (
        sys.executable,
        "-XRULES_PYTHON_ZIP_DIR=" + str(root.parent),
        "-m",
        "debugpy",
        str(root / app.entry),
        "argument with spaces",
    )
    assert command.cwd == str(root / "_main")
    assert command.environment == {
        "PYTHONSAFEPATH": "",
        "RUN_UNDER_RUNFILES": "1",
        "RUNFILES_DIR": str(root),
    }
    assert inherited["RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS"] == "-Xagain"


def test_old_python_template_expansion_keeps_public_arguments(tmp_path):
    files = runfiles.CreateOrRaise()
    path = files.Rlocation(os.environ["PY_TEMPLATE_RLOCATION"])
    assert path is not None
    template = Path(path).read_text()
    root = tmp_path / "runfiles"
    root.mkdir()
    (root / "probe.py").write_text(
        "import sys; assert sys._xoptions['legacy'] == 'works'\n"
    )
    substitutions = {
        "%shebang%": "#!/usr/bin/env python3",
        "%main%": "probe.py",
        "%python_binary%": Path(sys.executable).as_posix(),
        "%python_binary_actual%": Path(sys.executable).as_posix(),
        "%interpreter_args%": "-Xlegacy=works",
        "%runtime_venv_symlinks%": "",
        "%is_zipfile%": "0",
        "%recreate_venv_at_runtime%": "0",
        "%resolve_python_binary_at_runtime%": "0",
        "%workspace_name%": "_main",
    }
    for key, value in substitutions.items():
        template = template.replace(key, value)
    script = tmp_path / "legacy.py"
    script.write_text(template)
    result = subprocess.run(
        [sys.executable, str(script)],
        env=dict(os.environ, RUNFILES_DIR=str(root)),
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
