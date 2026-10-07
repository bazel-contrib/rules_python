"""Exercise generated launchers without replacing their process or signals."""

import contextlib
import json
import os
import pty
import re
import select
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import threading
import time
import zipfile
from pathlib import Path

import pytest

from python.runfiles import runfiles


def wait_until(predicate, description):
    deadline = time.monotonic() + 10
    while not predicate():
        assert time.monotonic() < deadline, description
        time.sleep(0.01)


class Launcher:
    def __init__(self, root, mode):
        self.root = root
        self.mode = mode
        self.shell = mode in (
            "venv",
            "zip",
            "zipapp",
            "zipapp_compressed",
            "wrapper",
            "wrapper_zip",
        )
        self.archive = mode not in ("venv", "pyvenv", "wrapper")
        self.temporary_runtime = (
            mode != "pyvenv" or os.environ["PYVENV_TEMPORARY"] == "1"
        )
        self.files = runfiles.CreateOrRaise()
        self.scratch = root / "temporary runtime with spaces"
        self.scratch.mkdir()
        self.environment = dict(os.environ, TMPDIR=str(self.scratch))
        for key in (
            "RULES_PYTHON_EXTRACT_ROOT",
            "RULES_PYTHON_BOOTSTRAP_VERBOSE",
            "RUNFILES_DIR",
            "RUNFILES_MANIFEST_FILE",
        ):
            self.environment.pop(key, None)
        self.binary = root / "launcher with spaces"
        source = self.locate(mode.upper() + "_RLOCATION")
        if self.archive:
            self.binary.symlink_to(source)
        else:
            shutil.copyfile(source, self.binary)
            self.binary.chmod(0o755)
        Path(str(self.binary) + ".runfiles").symlink_to(self.files.root())
        self.command = [
            os.environ.get("BOOTSTRAP_TEST_BASH", "/bin/bash")
            if self.shell
            else sys.executable,
            str(self.binary),
        ]

    def locate(self, name):
        result = self.files.Rlocation(os.environ[name])
        assert result is not None, name
        return result

    def replace_template_path(self, variable, location):
        assert self.mode == "venv"
        source, count = re.subn(
            rf"^{variable}=.*$",
            f"{variable}={shlex.quote(location)}",
            self.binary.read_text(),
            flags=re.MULTILINE,
        )
        assert count == 1
        self.binary.write_text(source)

    def run(self, *arguments, environment=None, command=None):
        return subprocess.run(
            [*(command or self.command), *arguments],
            env=environment or self.environment,
            input="input with spaces",
            text=True,
            capture_output=True,
            timeout=20,
            check=False,
        )

    def cleaned(self):
        wait_until(lambda: not list(self.scratch.iterdir()), "temporary runtime leaked")

    @contextlib.contextmanager
    def process(self, *arguments, environment=None, **kwargs):
        process = subprocess.Popen(
            [*self.command, *arguments],
            env=environment or self.environment,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
            **kwargs,
        )
        try:
            yield process
        finally:
            if process.poll() is None:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=10)
            self.cleaned()


@pytest.fixture(
    name="launcher",
    params=[
        "venv",
        "zip",
        "pyvenv",
        "pyzip",
        "legacy_python",
        "zipapp",
        "zipapp_python",
        "zipapp_compressed",
        "zipapp_system",
    ],
)
def fixture_launcher(tmp_path, request):
    return Launcher(tmp_path, request.param)


@pytest.fixture(name="venv")
def fixture_venv(tmp_path):
    return Launcher(tmp_path, "venv")


@pytest.fixture(name="shell_launcher", params=["zip", "zipapp"])
def fixture_shell_launcher(tmp_path, request):
    return Launcher(tmp_path, request.param)


@pytest.mark.parametrize("status", [0, 17, 143])
def test_spaces_tmpdir_stdin_arguments_and_status(launcher, status):
    result = launcher.run("echo", str(status), "argument with spaces")
    assert result.returncode == status, result.stderr
    actual = json.loads(result.stdout)
    assert actual["argv"] == ["argument with spaces"]
    assert actual["stdin"] == "input with spaces"
    assert (
        Path(actual["executable"]).is_relative_to(launcher.scratch)
        == launcher.temporary_runtime
    )
    assert actual["ignored"] == [False, False]
    assert (
        actual["xoptions"]["bootstrap_target"]
        == "argument with spaces and 'quotes' and \"double quotes\""
    )
    launcher.cleaned()


def test_persistent_extract_root(venv):
    extract_root = venv.root / "persistent runtime with spaces"
    result = venv.run(
        "echo",
        "0",
        environment=dict(venv.environment, RULES_PYTHON_EXTRACT_ROOT=str(extract_root)),
    )
    assert result.returncode == 0, result.stderr
    assert Path(json.loads(result.stdout)["executable"]).is_relative_to(extract_root)
    assert list(extract_root.iterdir())
    venv.cleaned()


@pytest.mark.parametrize("mode", ["wrapper", "wrapper_zip", "wrapper_zip_python"])
def test_runtime_handoff_resolves_wrapper_once_and_preserves_basename(tmp_path, mode):
    launcher = Launcher(tmp_path, mode)
    environment = startup_environment(launcher)
    environment["CLEANUP_REAL_INTERPRETER"] = sys.executable
    environment["CLEANUP_WRAPPER_DATA"] = os.environ["WRAPPER_DATA_RLOCATION"]
    environment["RUNFILES_MANIFEST_FILE"] = str(tmp_path / "unrelated manifest")
    result = launcher.run("echo", "0", environment=environment)
    assert result.returncode == 0, result.stderr
    actual = json.loads(result.stdout)
    assert Path(actual["executable"]).name == "cleanup_python_wrapper.sh"
    assert actual["handler"] == "user_interrupt"
    launcher.cleaned()


def test_shell_handoff_preserves_read_array_parsing(venv):
    result = venv.run(
        "echo",
        "0",
        environment=dict(
            venv.environment,
            RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS="-Xread_array=two\\ words\n-Xignored_second_line=1",
        ),
    )
    assert result.returncode == 0, result.stderr
    options = json.loads(result.stdout)["xoptions"]
    assert options["read_array"] == "two words"
    assert "ignored_second_line" not in options
    venv.cleaned()


def test_shell_handoff_exports_selected_runfiles_with_manifest(venv):
    root = venv.root / "provided.runfiles"
    root.symlink_to(os.fspath(venv.files.root()), target_is_directory=True)
    manifest = venv.root / "provided.runfiles_manifest"
    manifest.write_text(
        os.environ["TEST_WORKSPACE"] + "/fixture " + str(venv.binary) + "\n"
    )
    result = venv.run(
        "echo",
        "0",
        environment=dict(
            venv.environment,
            RUNFILES_MANIFEST_FILE=str(manifest),
        ),
    )
    assert result.returncode == 0, result.stderr
    assert Path(json.loads(result.stdout)["runfiles"]) == root
    venv.cleaned()


def test_shell_handoff_finds_interpreter_on_path(venv):
    directory = venv.root / "interpreter on path"
    directory.mkdir()
    (directory / "python3").symlink_to(sys.executable)
    venv.replace_template_path("PYTHON_BINARY_ACTUAL", "python3")
    venv.replace_template_path("INTERPRETER_KIND", "path")
    result = venv.run(
        "echo",
        "0",
        environment=dict(
            venv.environment,
            PATH=str(directory) + os.pathsep + venv.environment["PATH"],
        ),
    )
    assert result.returncode == 0, result.stderr
    venv.cleaned()


def test_caller_ignored_signals(launcher):
    result = launcher.run(
        "echo",
        "0",
        command=[
            "/bin/bash",
            "-c",
            'trap "" INT QUIT; exec "$@"',
            "ignored",
            *launcher.command,
        ],
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["ignored"] == [True, True]
    launcher.cleaned()


def test_application_can_wait_for_all_children(launcher):
    result = launcher.run("wait_children")
    assert result.returncode == 0, result.stderr
    launcher.cleaned()


@pytest.mark.parametrize(
    "value", [signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT]
)
@pytest.mark.parametrize("group", [False, True])
def test_signal_waits_for_application_cleanup(launcher, value, group):
    with launcher.process("handled", str(launcher.root)) as process:
        wait_until(
            lambda: (launcher.root / "ready").exists(), "application did not start"
        )
        assert int((launcher.root / "ready").read_text()) == process.pid
        if group:
            os.killpg(process.pid, value)
        else:
            process.send_signal(value)
        wait_until(
            lambda: (launcher.root / "stopping").exists(), "cancellation did not arrive"
        )
        assert process.poll() is None
        assert bool(list(launcher.scratch.iterdir())) == launcher.temporary_runtime
        process.send_signal(signal.SIGTERM)
        process.send_signal(signal.SIGHUP)
        assert process.stdin is not None
        process.stdin.write("cleanup\n")
        process.stdin.flush()
        stdout, stderr = process.communicate(timeout=10)
        assert process.returncode == 128 + value, stdout + stderr
        assert (launcher.root / "cleaned").exists()


def test_one_group_interrupt_does_not_interrupt_finally_twice(launcher):
    with launcher.process("interrupt", str(launcher.root)) as process:
        wait_until(
            lambda: (launcher.root / "ready").exists(), "application did not start"
        )
        os.killpg(process.pid, signal.SIGINT)
        wait_until(
            lambda: (launcher.root / "stopping").exists(), "finally did not start"
        )
        assert process.stdin is not None
        process.stdin.write("cleanup\n")
        process.stdin.flush()
        stdout, stderr = process.communicate(timeout=10)
        assert process.returncode in (-signal.SIGINT, 130), stdout + stderr
        assert (launcher.root / "cleaned").exists()


@pytest.mark.parametrize("value", [signal.SIGTERM, signal.SIGKILL])
def test_default_signal_status_and_cleanup(launcher, value):
    with launcher.process("default", str(launcher.root)) as process:
        wait_until(
            lambda: (launcher.root / "ready").exists(), "application did not start"
        )
        os.killpg(process.pid, value)
        process.communicate(timeout=10)
        assert process.returncode == -value


def test_custom_stage2_keeps_default_signal_dispositions(venv):
    venv.replace_template_path("STAGE2_BOOTSTRAP", os.environ["PROBE_RLOCATION"])
    result = venv.run("echo", "0")
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["ignored"] == [False, False]
    venv.cleaned()


def startup_environment(launcher):
    startup = launcher.root / "user startup"
    startup.mkdir()
    shutil.copyfile(launcher.locate("STARTUP_RLOCATION"), startup / "sitecustomize.py")
    return dict(launcher.environment, PYTHONPATH=str(startup))


def test_sitecustomize_handler_and_interpreter_arguments(launcher):
    environment = startup_environment(launcher)
    environment["RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS"] = "-Xbootstrap_probe=1"
    result = launcher.run("echo", "0", environment=environment)
    assert result.returncode == 0, result.stderr
    actual = json.loads(result.stdout)
    assert actual["handler"] == "user_interrupt"
    assert actual["xoptions"]["bootstrap_probe"] == "1"
    assert actual["additional_args"] is None
    launcher.cleaned()


def test_interpreter_argument_precedence_and_safe_path_optout(launcher):
    result = launcher.run(
        "echo",
        "0",
        environment=dict(
            launcher.environment,
            PYTHONSAFEPATH="",
            RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS="-Xbootstrap_precedence=additional",
        ),
    )
    assert result.returncode == 0, result.stderr
    actual = json.loads(result.stdout)
    assert actual["xoptions"]["bootstrap_precedence"] == (
        "target" if launcher.shell else "additional"
    )
    assert actual["safe_path"] == ""
    assert actual["additional_args"] is None
    launcher.cleaned()


def test_nested_launcher_does_not_reconsume_additional_args(launcher):
    result = launcher.run(
        "nested",
        *launcher.command,
        "echo",
        "0",
        environment=dict(
            launcher.environment,
            RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS="-Xouter_only=1",
        ),
    )
    assert result.returncode == 0, result.stderr
    actual = json.loads(result.stdout)
    assert "outer_only" not in actual["xoptions"]
    assert actual["additional_args"] is None
    launcher.cleaned()


@pytest.mark.parametrize(
    "mode", ["pyvenv", "pyzip", "legacy_python", "zipapp_python", "zipapp_system"]
)
def test_python_debugger_injection(tmp_path, mode):
    launcher = Launcher(tmp_path, mode)
    debugger = tmp_path / "debugger.py"
    debugger.write_text(
        "import runpy, sys\nassert sys.argv[1] == '--file'\nsys.argv = sys.argv[2:]\nrunpy.run_path(sys.argv[0], run_name='__main__')\n"
    )
    result = launcher.run(
        "echo",
        "0",
        environment=dict(
            launcher.environment,
            RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS=shlex.join(
                [str(debugger), "--file"]
            ),
        ),
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["additional_args"] is None
    launcher.cleaned()


def test_relative_tmpdir_and_zip_working_directory(launcher):
    environment = dict(
        launcher.environment,
        TMPDIR=os.path.relpath(launcher.scratch),
        RUN_UNDER_RUNFILES="1",
    )
    result = launcher.run("echo", "0", environment=environment)
    assert result.returncode == 0, result.stderr
    actual = json.loads(result.stdout)
    assert (
        Path(actual["executable"]).is_relative_to(launcher.scratch)
        == launcher.temporary_runtime
    )
    if launcher.archive:
        assert actual["cwd"] == os.path.normpath(
            str(Path(actual["runfiles"]) / os.environ["TEST_WORKSPACE"])
        )
    launcher.cleaned()


@pytest.mark.parametrize(
    "mode", ["zipapp", "zipapp_python", "zipapp_compressed", "zipapp_system"]
)
def test_persistent_zip_reuse_and_concurrent_publication(tmp_path, mode):
    launcher = Launcher(tmp_path, mode)
    root = tmp_path / "persistent cache with spaces"
    environment = dict(
        launcher.environment, RULES_PYTHON_EXTRACT_ROOT=os.path.relpath(root)
    )
    with contextlib.ExitStack() as resources:
        processes = [
            resources.enter_context(
                launcher.process("echo", "0", environment=environment)
            )
            for _ in range(4)
        ]
        results = [
            process.communicate("input with spaces", timeout=30)
            for process in processes
        ]
        for process, (_, stderr) in zip(processes, results):
            assert process.returncode == 0, stderr
    records = [json.loads(stdout) for stdout, _ in results]
    assert len({record["executable"] for record in records}) == 1
    assert len(list(root.rglob(".rules_python_complete"))) == 1
    assert not list(root.rglob(".rules_python.*"))
    assert all("RULES_PYTHON_ZIP_DIR" not in record["xoptions"] for record in records)
    first = records[0]
    sentinel = Path(first["runfiles"]) / "caller-kept"
    sentinel.write_text("preserve completed runtime")
    result = launcher.run("echo", "0", environment=environment)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["executable"] == first["executable"]
    assert sentinel.read_text() == "preserve completed runtime"
    launcher.cleaned()


@pytest.mark.parametrize("mode", ["zip", "pyzip", "legacy_python"])
def test_legacy_zip_does_not_cache_links_into_temporary_extraction(tmp_path, mode):
    launcher = Launcher(tmp_path, mode)
    root = tmp_path / "persistent root"
    root.mkdir()
    (root / "keep").touch()
    environment = dict(launcher.environment, RULES_PYTHON_EXTRACT_ROOT=str(root))
    for _ in range(2):
        result = launcher.run("echo", "0", environment=environment)
        assert result.returncode == 0, result.stderr
        assert Path(json.loads(result.stdout)["executable"]).is_relative_to(
            launcher.scratch
        )
        launcher.cleaned()
    assert [path.name for path in root.iterdir()] == ["keep"]


def test_warm_shell_zip_executes_without_preparation(tmp_path):
    launcher = Launcher(tmp_path, "zipapp")
    cache = tmp_path / "cache"
    environment = dict(launcher.environment, RULES_PYTHON_EXTRACT_ROOT=str(cache))
    cold = launcher.run("echo", "0", environment=environment)
    assert cold.returncode == 0, cold.stderr
    prepared = json.loads(cold.stdout)
    runfiles_root = Path(prepared["runfiles"])
    sentinel = runfiles_root / "caller-kept"
    sentinel.write_text("keep")

    payload = launcher.binary.read_bytes()
    payload, count = re.subn(
        rb"^BOOTSTRAP_DRIVER=.*$", b"BOOTSTRAP_DRIVER=must-not-run", payload, flags=re.M
    )
    assert count == 1
    launcher.binary.unlink()
    launcher.binary.write_bytes(payload)
    tools = tmp_path / "tools"
    tools.mkdir()
    for name in ("mktemp", "unzip"):
        tool = tools / name
        tool.write_text("#!/bin/sh\nexit 97\n")
        tool.chmod(0o755)
    environment.update(
        PATH=str(tools) + os.pathsep + environment["PATH"],
        RUN_UNDER_RUNFILES="1",
        RULES_PYTHON_ADDITIONAL_INTERPRETER_ARGS="-Xwarm_cache=once",
    )
    result = launcher.run("echo", "17", "warm argument", environment=environment)
    assert result.returncode == 17, result.stderr
    actual = json.loads(result.stdout)
    assert actual["argv"] == ["warm argument"]
    assert actual["runfiles"] == prepared["runfiles"]
    assert actual["executable"] == prepared["executable"]
    assert Path(actual["cwd"]).samefile(runfiles_root / os.environ["TEST_WORKSPACE"])
    assert actual["xoptions"]["warm_cache"] == "once"
    assert "RULES_PYTHON_ZIP_DIR" not in actual["xoptions"]
    assert sentinel.read_text() == "keep"
    launcher.cleaned()

    # A failed native exec must not take ownership of the completed image.
    invalid = runfiles_root / "invalid-executable"
    invalid.write_text("#!/nonexistent/interpreter\n")
    invalid.chmod(0o755)
    payload, count = re.subn(
        rb"^PYTHON_BINARY=.*$", b"PYTHON_BINARY=invalid-executable", payload, flags=re.M
    )
    assert count == 1
    launcher.binary.write_bytes(payload)
    failed = launcher.run("echo", "0", environment=environment)
    assert failed.returncode != 0
    assert sentinel.read_text() == "keep"
    assert list(cache.rglob(".rules_python_complete"))
    launcher.cleaned()


def test_standalone_archive(launcher):
    if not launcher.archive:
        pytest.skip("ordinary binary requires runfiles")
    Path(str(launcher.binary) + ".runfiles").unlink()
    # Copy the bytes too: do not let the test depend on a Bazel output symlink.
    archive = launcher.binary.resolve()
    launcher.binary.unlink()
    shutil.copyfile(archive, launcher.binary)
    result = launcher.run("echo", "0")
    assert result.returncode == 0, result.stderr
    launcher.cleaned()


@pytest.mark.parametrize(
    "mode", ["zip", "pyzip", "legacy_python", "zipapp", "zipapp_python"]
)
def test_failed_partial_extraction_removes_owned_tree(tmp_path, mode):
    launcher = Launcher(tmp_path, mode)
    archive = launcher.binary.resolve()
    launcher.binary.unlink()
    shutil.copyfile(archive, launcher.binary)
    with zipfile.ZipFile(launcher.binary) as source:
        entry = next(
            info
            for info in source.infolist()
            if info.filename.endswith("cleanup_probe.py")
        )
        offset = entry.header_offset
    with launcher.binary.open("r+b") as stream:
        stream.seek(offset + 26)
        name_size, extra_size = struct.unpack("<HH", stream.read(4))
        stream.seek(offset + 30 + name_size + extra_size)
        byte = stream.read(1)
        stream.seek(-1, os.SEEK_CUR)
        stream.write(bytes([byte[0] ^ 0xFF]))
    result = launcher.run("echo", "0")
    assert result.returncode != 0, "corrupt member was silently accepted"
    assert not result.stdout
    launcher.cleaned()


def test_group_cancellation_between_mkdir_and_registration(shell_launcher):
    launcher = shell_launcher
    environment = dict(launcher.environment, ALLOCATION_BARRIER=str(launcher.root))
    command = [
        "/bin/bash",
        "-c",
        'mktemp() { local path; path=$(/usr/bin/mktemp "$@"); '
        'touch "$ALLOCATION_BARRIER/allocated"; '
        'while [[ ! -f "$ALLOCATION_BARRIER/release" ]]; do sleep .01; done; '
        'printf "%s\\n" "$path"; }; export -f mktemp; exec "$@"',
        "allocation-barrier",
        *launcher.command,
    ]
    with subprocess.Popen(
        command + ["echo", "0"],
        env=environment,
        start_new_session=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ) as process:
        try:
            wait_until(
                lambda: (launcher.root / "allocated").exists(),
                "allocation did not reach barrier",
            )
            os.killpg(process.pid, signal.SIGTERM)
            (launcher.root / "release").touch()
            stdout, stderr = process.communicate(timeout=10)
            assert process.returncode == 143, stdout + stderr
            assert not stdout
        finally:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=10)
    launcher.cleaned()


def test_direct_cancellation_reaps_slow_extraction(shell_launcher):
    launcher = shell_launcher
    tools = launcher.root / "tools"
    tools.mkdir()
    unzip = tools / "unzip"
    unzip.write_text(
        "#!/bin/bash\n"
        "trap 'touch \"$EXTRACTION_BARRIER/stopped\"; exit 143' TERM\n"
        'printf "%s\\n" "$$" > "$EXTRACTION_BARRIER/extractor"\n'
        "while true; do sleep .05; done\n"
    )
    unzip.chmod(0o755)
    environment = dict(
        launcher.environment,
        PATH=str(tools) + os.pathsep + launcher.environment["PATH"],
        EXTRACTION_BARRIER=str(launcher.root),
    )
    with launcher.process("echo", "0", environment=environment) as parent:
        wait_until(
            lambda: (launcher.root / "extractor").exists(), "extraction did not start"
        )
        parent.terminate()
        stdout, stderr = parent.communicate(timeout=10)
        assert parent.returncode == 143, stdout + stderr
        assert (launcher.root / "stopped").exists()
        extractor = int((launcher.root / "extractor").read_text())
        with pytest.raises(ProcessLookupError):
            os.kill(extractor, 0)


@pytest.mark.parametrize("invalid", ["truncated", "extra", "version", "ownership"])
def test_shell_rejects_invalid_preparation_result(shell_launcher, invalid):
    launcher = shell_launcher
    fields = ["1", "", "runfiles", "python", "entry", "unowned"]
    if invalid == "extra":
        fields.append("extra")
    elif invalid == "version":
        fields[0] = "2"
    record = b"\0".join(field.encode() for field in fields) + b"\0"
    if invalid == "truncated":
        record = record[:-1]
    result = launcher.root / "preparation-result"
    result.write_bytes(record)
    source = launcher.binary.read_bytes()
    command = re.compile(
        re.escape(
            b'run_preparer "$python_actual" -I -S "$RUNFILES_DIR/$BOOTSTRAP_DRIVER" '
            b"\\\n"
        )
        + rb"[ \t]+"
        + re.escape(b'prepare-archive "$workspace" "$image" "$cached"')
    )
    source, count = command.subn(
        b'cp "$PREPARATION_RESULT" "$workspace/invocation"', source
    )
    assert count == 1
    launcher.binary.unlink()
    launcher.binary.write_bytes(source)
    completed = launcher.run(
        "echo",
        "0",
        environment=dict(launcher.environment, PREPARATION_RESULT=str(result)),
    )
    assert completed.returncode != 0
    assert (
        "workspace ownership" in completed.stderr
        if invalid == "ownership"
        else "Invalid Python preparation result" in completed.stderr
    )
    assert not completed.stdout
    launcher.cleaned()


def test_cancellation_before_stage2(launcher):
    environment = startup_environment(launcher)
    environment["CLEANUP_STARTUP_PROBE"] = str(launcher.root)
    with launcher.process("echo", "0", environment=environment) as process:
        wait_until(
            lambda: (launcher.root / "starting").exists(), "interpreter did not start"
        )
        process.terminate()
        process.communicate(timeout=10)
        assert process.returncode == -signal.SIGTERM


def test_cleanup_readiness_failure_prevents_application_start(venv):
    venv.replace_template_path("BOOTSTRAP_CLEANUP", os.environ["FAIL_RLOCATION"])
    result = venv.run("echo", "0")
    assert result.returncode == 1
    assert "cleanup_fail.py" in result.stderr
    assert not result.stdout
    venv.cleaned()


def test_cancellation_before_helper_readiness(venv):
    venv.replace_template_path("BOOTSTRAP_CLEANUP", os.environ["FAIL_RLOCATION"])
    environment = dict(venv.environment, CLEANUP_HELPER_STARTUP_PROBE=str(venv.root))
    with venv.process("echo", "0", environment=environment) as process:
        wait_until(
            lambda: (venv.root / "helper_starting").exists(),
            "helper did not start",
        )
        process.terminate()
        process.communicate(timeout=10)
        assert process.returncode == -signal.SIGTERM
        helper_pid = int((venv.root / "helper_starting").read_text())
        with pytest.raises(ProcessLookupError):
            os.kill(helper_pid, 0)


def test_setup_failure_is_cleaned(venv):
    venv.replace_template_path("PYTHON_BINARY_ACTUAL", "missing/interpreter")
    result = venv.run("echo", "0")
    assert result.returncode != 0
    assert "missing/interpreter" in result.stderr
    venv.cleaned()


def sentinel_environment(launcher):
    environment = dict(launcher.environment)
    sentinels = []
    for name in ("zip_dir", "venv"):
        directory = launcher.root / ("caller-owned-" + name)
        directory.mkdir()
        sentinel = directory / "keep"
        sentinel.write_text("caller-owned")
        sentinels.append(sentinel)
        environment[name] = str(directory)
    return environment, sentinels


@pytest.mark.parametrize("allocation_fails", [False, True])
def test_inherited_path_variables_cannot_select_cleanup(launcher, allocation_fails):
    environment, sentinels = sentinel_environment(launcher)
    if allocation_fails:
        environment["TMPDIR"] = str(launcher.root / "missing temporary root")
    result = launcher.run("echo", "0", environment=environment)
    if not launcher.temporary_runtime:
        assert result.returncode == 0, result.stderr
        assert Path(json.loads(result.stdout)["executable"]).is_file()
    elif allocation_fails and not launcher.shell:
        # tempfile falls back from an invalid TMPDIR to the platform temp root.
        assert result.returncode == 0, result.stderr
        wait_until(
            lambda: not Path(json.loads(result.stdout)["executable"]).exists(),
            "fallback runtime leaked",
        )
    else:
        assert (result.returncode != 0) == allocation_fails, result.stderr
    launcher.cleaned()
    assert [path.read_text() for path in sentinels] == ["caller-owned"] * 2


def test_cancellation_during_temporary_directory_allocation(shell_launcher):
    launcher = shell_launcher
    environment, sentinels = sentinel_environment(launcher)
    result = launcher.run(
        "echo",
        "0",
        environment=environment,
        command=[
            "/bin/bash",
            "-c",
            'mktemp() { /usr/bin/mktemp "$@"; kill -TERM "$$"; }; '
            'export -f mktemp; exec "$@"',
            "cancel-allocation",
            *launcher.command,
        ],
    )
    assert result.returncode == 143, result.stderr
    assert not result.stdout
    launcher.cleaned()
    assert [path.read_text() for path in sentinels] == ["caller-owned"] * 2


def test_exec_failure_is_cleaned(venv):
    match = re.search(
        r"^BOOTSTRAP_CLEANUP=(.*)$", venv.binary.read_text(), re.MULTILINE
    )
    assert match is not None
    location = venv.files.Rlocation(shlex.split(match[1])[0])
    assert location is not None
    real_helper = Path(location).resolve()
    assert real_helper.is_file()
    helper = venv.root / "remove_prepared_interpreter.py"
    marker = venv.root / "prepared-executable"
    helper.write_text(
        "import os, runpy, sys\n"
        "from pathlib import Path\n"
        "pid = os.getpid()\n"
        f"status = runpy.run_path({str(real_helper)!r})['main']()\n"
        "if status == 0 and os.getpid() == pid:\n"
        "    executable = Path(sys.executable)\n"
        "    assert executable.is_relative_to(sys.argv[2])\n"
        "    assert executable.is_symlink()\n"
        f"    Path({str(marker)!r}).write_text(str(executable))\n"
        "    executable.unlink()\n"
        "sys.exit(status)\n"
    )
    venv.replace_template_path("BOOTSTRAP_CLEANUP", str(helper))
    result = venv.run("echo", "0")
    assert result.returncode != 0
    assert "FileNotFoundError" in result.stderr
    assert marker.is_file(), result.stderr
    assert marker.read_text() in result.stderr
    assert not result.stdout
    venv.cleaned()


def test_failed_stage2_is_cleaned(venv):
    venv.replace_template_path("STAGE2_BOOTSTRAP", "missing-stage2.py")
    result = venv.run("echo", "0")
    assert result.returncode != 0
    venv.cleaned()


def test_verbose_mode_retains_runtime(launcher):
    result = launcher.run(
        "echo",
        "0",
        environment=dict(launcher.environment, RULES_PYTHON_BOOTSTRAP_VERBOSE="1"),
    )
    assert result.returncode == 0, result.stderr
    assert Path(json.loads(result.stdout)["executable"]).is_file()
    if not launcher.shell:
        assert "rules_python bootstrap: launching interpreter" in result.stderr
        assert (
            "rules_python bootstrap: retaining workspace" in result.stderr
        ) == launcher.temporary_runtime
        if launcher.archive:
            assert "rules_python bootstrap: extracting archive" in result.stderr


def test_helper_does_not_retain_application_descriptors(launcher):
    read_fd, write_fd = os.pipe()
    try:
        with launcher.process(
            "close_fds", str(launcher.root), str(write_fd), pass_fds=(write_fd,)
        ) as process:
            os.close(write_fd)
            write_fd = -1
            wait_until(
                lambda: (launcher.root / "ready").exists(), "application did not start"
            )
            assert process.stdout is not None and process.stderr is not None
            for fd in (read_fd, process.stdout.fileno(), process.stderr.fileno()):
                assert select.select([fd], [], [], 5)[0], (
                    "cleanup helper retained a descriptor"
                )
                assert os.read(fd, 1) == b""
            assert process.poll() is None
            (launcher.root / "finish").touch()
            process.communicate(timeout=10)
            assert process.returncode == 0
    finally:
        os.close(read_fd)
        if write_fd >= 0:
            os.close(write_fd)


@contextlib.contextmanager
def terminal_session(launcher):
    shell_pid, terminal = pty.fork()
    if shell_pid == 0:
        os.execve(
            "/bin/bash",
            ["/bin/bash", "--noprofile", "--norc", "--noediting", "-i"],
            launcher.environment,
        )
    output = bytearray()
    finished = threading.Event()

    def collect_output():
        with contextlib.suppress(OSError):
            while not finished.is_set():
                if select.select([terminal], [], [], 0.1)[0]:
                    chunk = os.read(terminal, 65536)
                    if not chunk:
                        return
                    output.extend(chunk)

    reader = threading.Thread(target=collect_output)
    reader.start()
    try:
        yield shell_pid, terminal
    finally:
        # These fixtures have no application grandchildren. Detached cleanup
        # helpers must observe their real parents exiting and finish themselves.
        for marker in ("ready", "peer_ready"):
            path = launcher.root / marker
            if path.exists():
                with contextlib.suppress(ProcessLookupError):
                    pid = int(path.read_text())
                    if os.getsid(pid) == shell_pid:
                        os.kill(pid, signal.SIGKILL)
        with contextlib.suppress(ProcessLookupError):
            os.kill(shell_pid, signal.SIGKILL)
        finished.set()
        reader.join(timeout=2)
        os.close(terminal)
        os.waitpid(shell_pid, 0)
        print(output.decode(errors="replace"))
        launcher.cleaned()


def send_command(terminal, command):
    os.write(terminal, (shlex.join(command) + "\n").encode())


@pytest.mark.parametrize("ignored_continue", [False, True])
def test_foreground_input_and_job_control(launcher, ignored_continue):
    with terminal_session(launcher) as (shell_pid, terminal):
        command = [*launcher.command, "default", str(launcher.root)]
        if ignored_continue:
            command = [
                "/bin/bash",
                "-c",
                'trap "" CONT; exec "$@"',
                "ignored",
                *command,
            ]
        send_command(terminal, command)
        wait_until(
            lambda: (launcher.root / "ready").exists(),
            "terminal application did not start",
        )
        app_pid = int((launcher.root / "ready").read_text())
        assert os.tcgetpgrp(terminal) == os.getpgid(app_pid)

        os.write(terminal, b"\x1a")  # Ctrl-Z: stop the foreground job.
        wait_until(
            lambda: os.tcgetpgrp(terminal) == shell_pid,
            "shell did not recover foreground",
        )
        assert bool(list(launcher.scratch.iterdir())) == launcher.temporary_runtime
        stopped = launcher.root / "background-stop"
        # Wait in the owning shell for the new SIGTTIN stop. Sampling `ps`
        # here can observe the old Ctrl-Z stop before `bg` has run.
        os.write(
            terminal,
            (
                'bg; wait %+; printf "%s\\n" "$?" > ' + shlex.quote(str(stopped)) + "\n"
            ).encode(),
        )
        wait_until(
            lambda: stopped.exists() and bool(stopped.read_text()),
            "background terminal reader did not stop",
        )
        assert int(stopped.read_text()) == 128 + signal.SIGTTIN
        os.write(terminal, b"fg\n")
        wait_until(
            lambda: os.tcgetpgrp(terminal) == os.getpgid(app_pid),
            "fg did not restore the job",
        )
        os.write(terminal, b"finish\n")
        wait_until(
            lambda: (launcher.root / "cleaned").exists(), "foreground input was lost"
        )
        wait_until(
            lambda: os.tcgetpgrp(terminal) == shell_pid,
            "shell did not recover after exit",
        )
        launcher.cleaned()


def test_terminal_ctrl_c_preserves_finally_input(launcher):
    with terminal_session(launcher) as (shell_pid, terminal):
        send_command(terminal, [*launcher.command, "interrupt", str(launcher.root)])
        wait_until(
            lambda: (launcher.root / "ready").exists(),
            "terminal application did not start",
        )
        os.write(terminal, b"\x03")
        wait_until(
            lambda: (launcher.root / "stopping").exists(), "Ctrl-C did not reach Python"
        )
        os.write(terminal, b"cleanup\n")
        wait_until(
            lambda: (launcher.root / "cleaned").exists(),
            "Ctrl-C interrupted cleanup twice",
        )
        wait_until(
            lambda: os.tcgetpgrp(terminal) == shell_pid,
            "shell did not recover foreground",
        )


def test_pipeline_peer_keeps_terminal_access(launcher):
    # Keep the typed command below the terminal's canonical input line limit.
    launcher.environment["CLEANUP_TERMINAL_PYTHON"] = sys.executable
    launcher.environment["CLEANUP_TERMINAL_PEER"] = launcher.locate("PEER_RLOCATION")
    with terminal_session(launcher) as (shell_pid, terminal):
        application = shlex.join([*launcher.command, "pipeline", str(launcher.root)])
        peer = '"$CLEANUP_TERMINAL_PYTHON" "$CLEANUP_TERMINAL_PEER" ' + shlex.quote(
            str(launcher.root)
        )
        os.write(terminal, (application + " | " + peer + "\n").encode())
        wait_until(
            lambda: (launcher.root / "ready").exists(),
            "pipeline application did not start",
        )
        wait_until(
            lambda: (launcher.root / "peer_ready").exists(),
            "pipeline peer did not start",
        )
        app_pid = int((launcher.root / "ready").read_text())
        peer_pid = int((launcher.root / "peer_ready").read_text())
        assert os.getpgid(app_pid) == os.getpgid(peer_pid) == os.tcgetpgrp(terminal)
        os.write(terminal, b"finish\n")
        wait_until(
            lambda: (launcher.root / "peer_done").exists(),
            "pipeline peer lost terminal input",
        )
        wait_until(
            lambda: (launcher.root / "cleaned").exists(),
            "pipeline application did not finish",
        )
        wait_until(
            lambda: os.tcgetpgrp(terminal) == shell_pid,
            "shell did not recover after pipeline",
        )
