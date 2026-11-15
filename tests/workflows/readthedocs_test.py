"""Tests for Read the Docs build script."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from python.runfiles import runfiles


def _write_fake_bazel(bin_dir: Path, body: str) -> Path:
    bin_dir.mkdir(parents=True, exist_ok=True)
    fake_bazel = bin_dir / "bazel"
    fake_bazel.write_text(
        f"#!/usr/bin/env bash\nset -euo pipefail\n{body}\n", encoding="utf-8"
    )
    fake_bazel.chmod(0o755)
    return fake_bazel


def _rtd_script() -> Path:
    rf = runfiles.CreateOrRaise()
    return rf.root() / "rules_python/docs/readthedocs_build.sh"


def test_pr_uses_cas_only_and_presubmit(tmp_path: Path):
    """Verifies PR builds use BUILDBUDDY_CAS_ONLY_KEY and presubmit config."""
    calls_file = tmp_path / "bazel_calls.txt"
    _write_fake_bazel(
        tmp_path / "bin",
        f'printf "%s\\n" "$*" >> "{calls_file}"\n',
    )
    env = {
        "PATH": f"{tmp_path / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}",
        "HOME": str(tmp_path / "home"),
        "HOSTNAME": "build-999-project-1-rules-python",
        "READTHEDOCS": "True",
        "READTHEDOCS_VERSION": "4242",
        "READTHEDOCS_VERSION_TYPE": "external",
        "READTHEDOCS_GIT_IDENTIFIER": "4242",
        "READTHEDOCS_GIT_COMMIT_HASH": "deadbeef1234",
        "READTHEDOCS_OUTPUT": str(tmp_path / "out"),
        "BUILDBUDDY_CAS_ONLY_KEY": "rtd_cas_only_val",
        "BUILDBUDDY_READ_WRITE_KEY": "rtd_rw_val",
    }

    result = subprocess.run(
        [str(_rtd_script())],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )

    combined_output = result.stdout + result.stderr
    assert "rtd_cas_only_val" not in combined_output
    assert "rtd_rw_val" not in combined_output
    expected_rc = (
        "common:buildbuddy_presubmit "
        "--remote_header=x-buildbuddy-api-key=rtd_cas_only_val\n"
    )
    assert (tmp_path / "user.bazelrc").read_text(encoding="utf-8") == (expected_rc)

    calls = calls_file.read_text(encoding="utf-8").splitlines()
    assert len(calls) == 1
    run_call = calls[0]
    assert "--config=rtd" in run_call
    assert "--config=buildbuddy_presubmit" in run_call
    assert "--build_metadata=PR_NUMBER=4242" in run_call
    assert "--build_metadata=COMMIT_SHA=deadbeef1234" in run_call
    assert "--stamp" not in run_call
    assert "HOSTNAME" not in run_call
    assert "READTHEDOCS_OUTPUT" not in run_call
    assert "--@sphinxdocs//sphinxdocs:extra_env=READTHEDOCS=True" in run_call
    assert "READTHEDOCS_GIT_COMMIT_HASH" not in run_call
    assert "READTHEDOCS_GIT_IDENTIFIER" not in run_call
    assert "--@sphinxdocs//sphinxdocs:extra_env=READTHEDOCS_VERSION=" not in run_call


def test_non_pr_uses_read_write_and_stamps_tags(
    tmp_path: Path,
):
    """Verifies non-PR builds use BUILDBUDDY_READ_WRITE_KEY and stamp tags."""
    calls_file = tmp_path / "bazel_calls.txt"
    _write_fake_bazel(
        tmp_path / "bin",
        f'printf "%s\\n" "$*" >> "{calls_file}"\n',
    )
    base_env = {
        "PATH": f"{tmp_path / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}",
        "HOME": str(tmp_path / "home"),
        "READTHEDOCS": "True",
        "READTHEDOCS_GIT_COMMIT_HASH": "cafebabe5678",
        "BUILDBUDDY_CAS_ONLY_KEY": "rtd_cas_only_val",
        "BUILDBUDDY_READ_WRITE_KEY": "rtd_rw_val",
    }

    # 1. Branch build (latest / main): no --stamp
    branch_dir = tmp_path / "branch_run"
    branch_dir.mkdir()
    subprocess.run(
        [str(_rtd_script())],
        cwd=branch_dir,
        env={
            **base_env,
            "READTHEDOCS_VERSION": "latest",
            "READTHEDOCS_VERSION_TYPE": "branch",
            "READTHEDOCS_GIT_IDENTIFIER": "main",
        },
        capture_output=True,
        text=True,
        check=True,
    )
    expected_branch_rc = (
        "common:buildbuddy_postsubmit --remote_header=x-buildbuddy-api-key=rtd_rw_val\n"
    )
    assert (branch_dir / "user.bazelrc").read_text(encoding="utf-8") == (
        expected_branch_rc
    )

    # 2. Tag build (release): passes --stamp
    tag_dir = tmp_path / "tag_run"
    tag_dir.mkdir()
    subprocess.run(
        [str(_rtd_script())],
        cwd=tag_dir,
        env={
            **base_env,
            "READTHEDOCS_VERSION": "1.2.3",
            "READTHEDOCS_VERSION_TYPE": "tag",
            "READTHEDOCS_GIT_IDENTIFIER": "1.2.3",
        },
        capture_output=True,
        text=True,
        check=True,
    )

    calls = calls_file.read_text(encoding="utf-8").splitlines()
    assert len(calls) == 2
    branch_run_call = calls[0]
    tag_run_call = calls[1]

    assert "--config=buildbuddy_postsubmit" in branch_run_call
    assert "--build_metadata=BRANCH_NAME=main" in branch_run_call
    assert "--stamp" not in branch_run_call
    assert (
        "--@sphinxdocs//sphinxdocs:extra_env=READTHEDOCS_GIT_COMMIT_HASH=cafebabe5678"
        in branch_run_call
    )
    assert (
        "--@sphinxdocs//sphinxdocs:extra_env=READTHEDOCS_GIT_IDENTIFIER=main"
        in branch_run_call
    )
    assert (
        "--@sphinxdocs//sphinxdocs:extra_env=READTHEDOCS_VERSION=latest"
        in branch_run_call
    )

    assert "--config=buildbuddy_postsubmit" in tag_run_call
    assert "--build_metadata=BRANCH_NAME=1.2.3" in tag_run_call
    assert "--stamp" in tag_run_call
