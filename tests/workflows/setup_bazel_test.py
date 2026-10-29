"""Tests for the .github/actions/setup-bazel composite action."""

from __future__ import annotations

import hashlib
import os
import stat
import tarfile
from pathlib import Path

import download_bazel
import pytest
import yaml

from python.runfiles import runfiles


def _action_dir() -> Path:
    return runfiles.CreateOrRaise().root() / "rules_python/.github/actions/setup-bazel"


def _write_fake_bazel(bin_dir: Path, body: str, name: str = "bazel") -> Path:
    bin_dir.mkdir(parents=True, exist_ok=True)
    fake_bazel = bin_dir / name
    fake_bazel.write_text(
        f"#!/usr/bin/env bash\nset -euo pipefail\n{body}\n", encoding="utf-8"
    )
    fake_bazel.chmod(0o755)
    return fake_bazel


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_action_yaml_invokes_executable_download_script():
    """Verifies setup-bazel action.yaml runs download_bazel.py and omits bazelisk-version."""
    action_dir = _action_dir()
    script = action_dir / "download_bazel.py"
    assert script.is_file()
    assert bool(script.stat().st_mode & stat.S_IXUSR), (
        "download_bazel.py must be executable"
    )

    action = yaml.safe_load((action_dir / "action.yaml").read_text(encoding="utf-8"))
    steps = action["runs"]["steps"]
    assert any("download_bazel.py" in step.get("run", "") for step in steps)
    setup_step = next(s for s in steps if s.get("name") == "Setup Bazel")
    assert "bazelisk-version" not in setup_step["with"]


def test_action_yaml_enables_buildbuddy_on_all_os():
    """Verifies setup-bazel action.yaml enables BuildBuddy across all OSes."""
    action = yaml.safe_load((_action_dir() / "action.yaml").read_text(encoding="utf-8"))
    steps = action["runs"]["steps"]
    setup_step = next(s for s in steps if s.get("name") == "Setup Bazel")
    bazelrc = setup_step["with"]["bazelrc"]
    assert "inputs.buildbuddy_api_key" in bazelrc
    assert "runner.os" not in bazelrc
    assert "ROLE=CI" in bazelrc
    assert "VISIBILITY=PUBLIC" in bazelrc
    assert "RUN_ID=" in bazelrc
    assert "ACTOR=" in bazelrc
    assert "COMMIT_SHA=" in bazelrc
    assert "PR_NUMBER=" in bazelrc
    assert "BRANCH_NAME=" in bazelrc
    assert '--build_metadata="BUILDBUDDY_LINKS=' in bazelrc
    secret_step = next(
        s for s in steps if s.get("name") == "Write secret to user.bazelrc"
    )
    assert secret_step["if"] == "${{ inputs.buildbuddy_api_key != '' }}"


def test_buildbuddy_bazelrc_cache_and_diagnostics():
    """Verifies buildbuddy.bazelrc includes recommended cache, diagnostic, and
    profiling flags.
    """
    rf = runfiles.CreateOrRaise()
    buildbuddy_path = rf.root() / "rules_python/buildbuddy.bazelrc"
    buildbuddy_lines = [
        line.strip()
        for line in buildbuddy_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    expected_flags = [
        (
            "build:_buildbuddy_base "
            "--build_metadata=REPO_URL=https://github.com/bazel-contrib/rules_python"
        ),
        "common:_buildbuddy_base --remote_cache_compression",
        "common:_buildbuddy_base --experimental_remote_cache_chunking",
        "common:_buildbuddy_base --rewind_lost_inputs",
        "common:_buildbuddy_base --remote_grpc_log=bazel-remote-grpc.log",
        (
            "common:_buildbuddy_base "
            "--execution_log_compact_file=bazel-execution-log.binpb.zst"
        ),
        "common:_buildbuddy_base --noslim_profile",
        "common:_buildbuddy_base --experimental_profile_include_target_label",
        "common:_buildbuddy_base --experimental_profile_include_primary_output",
    ]
    for flag in expected_flags:
        assert flag in buildbuddy_lines, f"Expected '{flag}' in buildbuddy.bazelrc"


def test_buildbuddy_bazelrc_disables_remote_executor_on_macos_and_windows():
    """Verifies .bazelrc and buildbuddy.bazelrc disable remote_executor on macOS and Windows."""
    rf = runfiles.CreateOrRaise()
    buildbuddy_path = rf.root() / "rules_python/buildbuddy.bazelrc"
    buildbuddy_lines = [
        line.strip()
        for line in buildbuddy_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    executor_line = (
        "common:_buildbuddy_base --remote_executor=grpcs://rules-python.buildbuddy.io"
    )
    platform_config_line = "common:_buildbuddy_base --enable_platform_specific_config"
    assert executor_line in buildbuddy_lines
    assert platform_config_line in buildbuddy_lines
    assert buildbuddy_lines.index(executor_line) < buildbuddy_lines.index(
        platform_config_line
    )

    bazelrc_path = rf.root() / "rules_python/.bazelrc"
    bazelrc_lines = [
        line.strip()
        for line in bazelrc_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    assert "common:macos --remote_executor=" in bazelrc_lines
    assert "common:windows --remote_executor=" in bazelrc_lines


def test_download_bazelisk_from_primary_url(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    """Verifies download_bazel.py downloads Bazelisk, checks SHA-256, and updates GITHUB_PATH."""
    calls_file = tmp_path / "calls.txt"
    release_dir = tmp_path / "releases" / "v1.30.0"
    asset = _write_fake_bazel(
        release_dir,
        f'echo "$@" >> "{calls_file}"\necho "bazel 9.1.1"\n',
        name="bazelisk-linux-amd64",
    )
    github_path = tmp_path / "github_path"
    home = tmp_path / "home"

    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("XDG_CACHE_HOME", raising=False)
    monkeypatch.delenv("BAZELISK_HOME", raising=False)
    monkeypatch.setenv("GITHUB_PATH", str(github_path))
    monkeypatch.setattr(download_bazel, "_detect_os", lambda: "linux")
    monkeypatch.setattr(download_bazel, "_detect_arch", lambda: "amd64")
    monkeypatch.setitem(
        download_bazel.BAZELISK_URLS,
        "linux-amd64",
        [(asset.as_uri(), _sha256_file(asset))],
    )

    download_bazel.main()

    out = capsys.readouterr().out
    bin_dir = home / ".cache/bazelisk/bin"
    assert (bin_dir / "bazel").is_file()
    assert (bin_dir / "bazelisk").is_file()
    assert github_path.read_text(encoding="utf-8").splitlines() == [str(bin_dir)]
    assert calls_file.read_text(encoding="utf-8").splitlines() == ["--version"]
    assert "::warning::" not in out
    assert "::error::" not in out


def test_download_bazelisk_falls_back_to_npm_mirror(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    """Verifies download_bazel.py falls back to the npm tarball mirror when primary fails."""
    calls_file = tmp_path / "calls.txt"
    pkg_dir = tmp_path / "npm" / "package"
    asset = _write_fake_bazel(
        pkg_dir,
        f'echo "$@" >> "{calls_file}"\necho "bazel 9.1.1"\n',
        name="bazelisk-linux_amd64",
    )
    tgz_path = tmp_path / "bazelisk-1.28.1.tgz"
    with tarfile.open(tgz_path, "w:gz") as tar:
        tar.add(asset, arcname="package/bazelisk-linux_amd64")

    home = tmp_path / "home"
    missing_url = (tmp_path / "missing").as_uri()
    sha = _sha256_file(asset)

    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("XDG_CACHE_HOME", raising=False)
    monkeypatch.delenv("BAZELISK_HOME", raising=False)
    monkeypatch.setattr(download_bazel, "_detect_os", lambda: "linux")
    monkeypatch.setattr(download_bazel, "_detect_arch", lambda: "amd64")
    monkeypatch.setitem(
        download_bazel.BAZELISK_URLS,
        "linux-amd64",
        [(missing_url, sha), (tgz_path.as_uri(), sha)],
    )

    download_bazel.main()

    out = capsys.readouterr().out
    assert f"::warning::Failed to fetch {missing_url}" in out
    assert calls_file.read_text(encoding="utf-8").splitlines() == ["--version"]
    assert (home / ".cache/bazelisk/bin/bazel").is_file()


def test_download_bazelisk_reuses_cached_binary(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    """Verifies download_bazel.py reuses a cached Bazelisk binary with matching SHA-256."""
    calls_file = tmp_path / "calls.txt"
    home = tmp_path / "home"
    cached_bazel = _write_fake_bazel(
        home / ".cache/bazelisk/bin",
        f'echo "$@" >> "{calls_file}"\necho "bazel 9.1.1"\n',
        name="bazel",
    )

    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("XDG_CACHE_HOME", raising=False)
    monkeypatch.delenv("BAZELISK_HOME", raising=False)
    monkeypatch.setattr(download_bazel, "_detect_os", lambda: "linux")
    monkeypatch.setattr(download_bazel, "_detect_arch", lambda: "amd64")
    monkeypatch.setitem(
        download_bazel.BAZELISK_URLS,
        "linux-amd64",
        [((tmp_path / "missing").as_uri(), _sha256_file(cached_bazel))],
    )

    download_bazel.main()

    out = capsys.readouterr().out
    assert (home / ".cache/bazelisk/bin/bazelisk").is_file()
    assert calls_file.read_text(encoding="utf-8").splitlines() == ["--version"]
    assert "::warning::" not in out


def test_download_bazelisk_exhausts_retries_and_cleans_cache(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    """Verifies download_bazel.py cleans up cache dirs when Bazelisk download fails."""
    home = tmp_path / "home"
    (home / ".cache/bazelisk/partial").mkdir(parents=True, exist_ok=True)

    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("XDG_CACHE_HOME", raising=False)
    monkeypatch.delenv("BAZELISK_HOME", raising=False)
    monkeypatch.setattr(download_bazel, "_detect_os", lambda: "linux")
    monkeypatch.setattr(download_bazel, "_detect_arch", lambda: "amd64")
    monkeypatch.setitem(
        download_bazel.BAZELISK_URLS,
        "linux-amd64",
        [
            ((tmp_path / "missing").as_uri(), "0" * 64),
            ((tmp_path / "missing.tgz").as_uri(), "0" * 64),
        ],
    )

    with pytest.raises(SystemExit) as exc_info:
        download_bazel._setup_bazelisk(max_attempts=2, initial_delay=0)

    assert exc_info.value.code == 1
    out = capsys.readouterr().out
    assert "::error::Failed to download Bazelisk after 2 attempts" in out
    assert not (home / ".cache/bazelisk").exists()


def test_download_bazel_succeeds_first_try(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    """Verifies _download_bazel succeeds without warnings when bazel --version succeeds."""
    calls_file = tmp_path / "calls.txt"
    _write_fake_bazel(
        tmp_path / "bin",
        f'echo "$@" >> "{calls_file}"\necho "bazel 9.1.1"\n',
    )

    monkeypatch.setenv(
        "PATH", f"{tmp_path / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}"
    )
    monkeypatch.setenv("HOME", str(tmp_path / "home"))

    download_bazel._download_bazel(max_attempts=5, initial_delay=0)

    out = capsys.readouterr().out
    assert calls_file.read_text(encoding="utf-8").splitlines() == ["--version"]
    assert "::warning::" not in out
    assert "::error::" not in out


def test_download_bazel_retries_transient_failure(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    """Verifies _download_bazel retries transient failures and succeeds."""
    calls_file = tmp_path / "calls.txt"
    _write_fake_bazel(
        tmp_path / "bin",
        f"""
echo "$@" >> "{calls_file}"
count=$(wc -l < "{calls_file}")
if (( count < 3 )); then
  echo "could not download Bazel: stream error: INTERNAL_ERROR" >&2
  exit 1
fi
mkdir -p "$HOME/.cache/bazelisk/downloads"
echo "bazel 9.1.1"
""",
    )

    home = tmp_path / "home"
    monkeypatch.setenv(
        "PATH", f"{tmp_path / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}"
    )
    monkeypatch.setenv("HOME", str(home))

    download_bazel._download_bazel(max_attempts=5, initial_delay=0)

    out = capsys.readouterr().out
    assert calls_file.read_text(encoding="utf-8").splitlines() == [
        "--version",
        "--version",
        "--version",
    ]
    assert "::warning::Failed to download Bazel (attempt 1/5)" in out
    assert "::warning::Failed to download Bazel (attempt 2/5)" in out
    assert (home / ".cache/bazelisk/downloads").is_dir()


def test_download_bazel_exhausts_retries_and_cleans_cache(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    """Verifies _download_bazel cleans up partial cache dirs when all retries fail."""
    calls_file = tmp_path / "calls.txt"
    _write_fake_bazel(
        tmp_path / "bin",
        f"""
echo "$@" >> "{calls_file}"
mkdir -p "$HOME/.cache/bazelisk/downloads/_tmp"
mkdir -p "$BAZELISK_HOME/downloads/_tmp"
exit 1
""",
    )

    home = tmp_path / "home"
    bazelisk_home = tmp_path / "bazelisk_home"
    monkeypatch.setenv(
        "PATH", f"{tmp_path / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}"
    )
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("XDG_CACHE_HOME", raising=False)
    monkeypatch.setenv("BAZELISK_HOME", str(bazelisk_home))

    with pytest.raises(SystemExit) as exc_info:
        download_bazel._download_bazel(max_attempts=3, initial_delay=0)

    assert exc_info.value.code == 1
    out = capsys.readouterr().out
    assert len(calls_file.read_text(encoding="utf-8").splitlines()) == 3
    assert "::error::Failed to download Bazel after 3 attempts" in out
    assert not (home / ".cache/bazelisk").exists()
    assert not bazelisk_home.exists()
