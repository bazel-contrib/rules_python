"""Unit tests for BzlmodLockfileTest lockfile preservation and reporting."""

from __future__ import annotations

import os
import pathlib
import subprocess
from collections.abc import Callable, Sequence
from unittest import mock

import pytest

from tests.integration import bzlmod_lockfile_test

_STALE_LOCKFILE = b'{\n  "lockFileVersion": 1,\n  "digest": "aaaa"\n}\n'
_UPDATED_LOCKFILE = b'{\n  "lockFileVersion": 1,\n  "digest": "bbbb"\n}\n'
_EXPECTED_DIFF = (
    "--- MODULE.bazel.lock (checked-in)\n"
    "+++ MODULE.bazel.lock (expected/updated)\n"
    "@@ -1,4 +1,4 @@\n"
    " {\n"
    '   "lockFileVersion": 1,\n'
    '-  "digest": "aaaa"\n'
    '+  "digest": "bbbb"\n'
    " }\n"
)
# Distinct historical timestamp so tests verify mtime restoration in addition to
# byte contents.
_ORIGINAL_MTIME_NS = 1_700_000_000_000_000_000


@pytest.fixture(name="lockfile_env")
def fixture_lockfile_env(
    tmp_path: pathlib.Path, monkeypatch: pytest.MonkeyPatch
) -> tuple[pathlib.Path, pathlib.Path]:
    """Sets up `runner.TestCase` environment variables and workspace files.

    Args:
        tmp_path: Per-test temporary directory.
        monkeypatch: Pytest monkeypatch helper.

    Returns:
        Tuple of `(lockfile_path, undeclared_outputs_dir)` inside `tmp_path`.
    """
    workspace_dir = tmp_path / "workspace"
    workspace_dir.mkdir()
    lockfile_path = workspace_dir / "MODULE.bazel.lock"
    lockfile_path.write_bytes(_STALE_LOCKFILE)
    os.utime(lockfile_path, ns=(_ORIGINAL_MTIME_NS, _ORIGINAL_MTIME_NS))

    # runner.TestCase.setUp opens BIT_BAZEL_BINARY on Windows to inspect any
    # shebang line, so point it at an existing file.
    fake_bazel = tmp_path / "fake_bazel"
    fake_bazel.write_bytes(b"")

    test_tmpdir = tmp_path / "test_tmpdir"
    test_tmpdir.mkdir()
    runfiles_dir = tmp_path / "runfiles"
    runfiles_dir.mkdir()
    undeclared_outputs_dir = tmp_path / "undeclared_outputs"
    undeclared_outputs_dir.mkdir()

    monkeypatch.setenv("BIT_WORKSPACE_DIR", str(workspace_dir))
    monkeypatch.setenv("BIT_BAZEL_BINARY", str(fake_bazel))
    monkeypatch.setenv("TEST_TMPDIR", str(test_tmpdir))
    monkeypatch.setenv("TEST_SRCDIR", str(runfiles_dir))
    monkeypatch.setenv("TEST_UNDECLARED_OUTPUTS_DIR", str(undeclared_outputs_dir))
    monkeypatch.setenv("RULES_PYTHON_INTEGRATION_TEST_BZLMOD", "1")
    return lockfile_path, undeclared_outputs_dir


def _run_case() -> None:
    case = bzlmod_lockfile_test.BzlmodLockfileTest("test_bzlmod_lockfile")
    case.setUp()
    try:
        case.test_bzlmod_lockfile()
    finally:
        case.tearDown()


def _assert_lockfile_preserved(
    lockfile_path: pathlib.Path, expected_bytes: bytes
) -> None:
    assert lockfile_path.read_bytes() == expected_bytes
    assert lockfile_path.stat().st_mtime_ns == _ORIGINAL_MTIME_NS


def _make_bazel_simulator(
    lockfile_path: pathlib.Path,
    *,
    force_test_failure_stderr: str | None = None,
) -> Callable[..., subprocess.CompletedProcess[str]]:
    """Builds a `subprocess.run` side effect simulating inner Bazel commands."""

    def _fake_run(
        args: Sequence[str], **_kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        cmd_list = list(args)
        subcommand = cmd_list[1]
        if subcommand == "test":
            if force_test_failure_stderr is not None:
                return subprocess.CompletedProcess(
                    cmd_list, 1, stdout="", stderr=force_test_failure_stderr
                )
            if lockfile_path.read_bytes() == _UPDATED_LOCKFILE:
                return subprocess.CompletedProcess(cmd_list, 0, stdout="", stderr="")
            return subprocess.CompletedProcess(
                cmd_list, 1, stdout="", stderr="ERROR: Lockfile is out of date\n"
            )
        if subcommand == "mod":
            lockfile_path.write_bytes(_UPDATED_LOCKFILE)
            return subprocess.CompletedProcess(cmd_list, 0, stdout="", stderr="")
        raise AssertionError(f"Unexpected bazel subcommand: {cmd_list}")

    return _fake_run


def test_passes_when_up_to_date(
    lockfile_env: tuple[pathlib.Path, pathlib.Path],
) -> None:
    lockfile_path, undeclared_outputs_dir = lockfile_env
    lockfile_path.write_bytes(_UPDATED_LOCKFILE)
    os.utime(lockfile_path, ns=(_ORIGINAL_MTIME_NS, _ORIGINAL_MTIME_NS))

    with mock.patch.object(
        subprocess,
        "run",
        autospec=True,
        side_effect=_make_bazel_simulator(lockfile_path),
    ) as mock_run:
        _run_case()

    assert mock_run.call_count == 1
    _assert_lockfile_preserved(lockfile_path, _UPDATED_LOCKFILE)
    assert list(undeclared_outputs_dir.iterdir()) == []


def test_restores_lockfile_across_retries_on_mismatch(
    lockfile_env: tuple[pathlib.Path, pathlib.Path],
) -> None:
    lockfile_path, undeclared_outputs_dir = lockfile_env

    with mock.patch.object(
        subprocess,
        "run",
        autospec=True,
        side_effect=_make_bazel_simulator(lockfile_path),
    ):
        # Simulate `--flaky_test_attempts=2`: both attempt 1 and attempt 2 must
        # fail identically because attempt 1 restores the stale lockfile.
        for _ in range(2):
            with pytest.raises(
                AssertionError, match=r"MODULE\.bazel\.lock is out of date\."
            ) as exc_info:
                _run_case()
            assert _EXPECTED_DIFF in str(exc_info.value)
            _assert_lockfile_preserved(lockfile_path, _STALE_LOCKFILE)

    assert (
        undeclared_outputs_dir / "MODULE.bazel.lock"
    ).read_bytes() == _UPDATED_LOCKFILE
    assert (undeclared_outputs_dir / "MODULE.bazel.lock.diff").read_text(
        encoding="utf-8"
    ) == _EXPECTED_DIFF


def test_reports_test_failure_when_lockfile_matches(
    lockfile_env: tuple[pathlib.Path, pathlib.Path],
) -> None:
    lockfile_path, undeclared_outputs_dir = lockfile_env
    lockfile_path.write_bytes(_UPDATED_LOCKFILE)
    os.utime(lockfile_path, ns=(_ORIGINAL_MTIME_NS, _ORIGINAL_MTIME_NS))

    with mock.patch.object(
        subprocess,
        "run",
        autospec=True,
        side_effect=_make_bazel_simulator(
            lockfile_path,
            force_test_failure_stderr="FAIL: //:test_dummy\n",
        ),
    ):
        with pytest.raises(
            AssertionError, match=r"bazel test //\.\.\. failed:"
        ) as exc_info:
            _run_case()

    assert "FAIL: //:test_dummy" in str(exc_info.value)
    _assert_lockfile_preserved(lockfile_path, _UPDATED_LOCKFILE)
    assert not (undeclared_outputs_dir / "MODULE.bazel.lock.diff").exists()


def test_restores_lockfile_when_update_raises(
    lockfile_env: tuple[pathlib.Path, pathlib.Path],
) -> None:
    lockfile_path, _ = lockfile_env

    def _mutating_crash(
        args: Sequence[str], **_kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        cmd_list = list(args)
        if cmd_list[1] == "test":
            return subprocess.CompletedProcess(cmd_list, 1, stdout="", stderr="")
        lockfile_path.write_bytes(_UPDATED_LOCKFILE)
        raise OSError("simulated bazel crash after partial lockfile write")

    with mock.patch.object(
        subprocess, "run", autospec=True, side_effect=_mutating_crash
    ):
        with pytest.raises(OSError, match="simulated bazel crash"):
            _run_case()

    _assert_lockfile_preserved(lockfile_path, _STALE_LOCKFILE)
