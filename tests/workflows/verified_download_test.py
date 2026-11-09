"""Tests for the .github/actions/download-tool composite action and module."""

from __future__ import annotations

import asyncio
import hashlib
import stat
import tarfile
import zipfile
from pathlib import Path

import pytest
import verified_download
import yaml
from verified_download import (
    DownloadError,
    download_verified_file,
    parse_url_list,
)

from python.runfiles import runfiles


def _action_dir() -> Path:
    return (
        runfiles.CreateOrRaise().root() / "rules_python/.github/actions/download-tool"
    )


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def test_action_yaml_accepts_urls_and_caches_by_name_and_sha256() -> None:
    rf = runfiles.CreateOrRaise()
    action_dir = _action_dir()
    script = rf.root() / "rules_python/dev/verified_download.py"
    assert script.is_file()
    assert bool(script.stat().st_mode & stat.S_IXUSR)

    action = yaml.safe_load((action_dir / "action.yaml").read_text(encoding="utf-8"))
    assert set(action["inputs"].keys()) == {"name", "urls", "sha256"}
    assert action["outputs"]["path"]["value"] == "${{ steps.tool_path.outputs.path }}"

    steps = action["runs"]["steps"]
    for step in steps:
        assert "${{" not in step.get("run", "")

    cache_step = next(s for s in steps if s.get("id") == "cache")
    assert cache_step["uses"].startswith("actions/cache@")
    assert cache_step["with"]["path"] == "${{ steps.tool_path.outputs.path }}"
    assert cache_step["with"]["key"] == "${{ inputs.name }}-${{ inputs.sha256 }}"

    download_step = next(
        s for s in steps if s.get("name") == "Download and verify tool"
    )
    assert download_step["if"] == "steps.cache.outputs.cache-hit != 'true'"
    assert download_step["env"]["TOOL_URLS"] == "${{ inputs.urls }}"
    assert '--urls "${TOOL_URLS}"' in download_step["run"]
    assert "dev/verified_download.py" in download_step["run"]


def test_parse_url_list_splits_commas_and_newlines() -> None:
    urls = parse_url_list(
        "https://primary.example.com/tool, https://mirror.example.com/tool,\n"
        "  https://backup.example.com/tool\n"
    )
    assert urls == [
        "https://primary.example.com/tool",
        "https://mirror.example.com/tool",
        "https://backup.example.com/tool",
    ]
    with pytest.raises(ValueError, match="At least one URL"):
        parse_url_list(" ,\n ")


def test_downloads_from_delimited_url_list_with_fallback(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    payload = b"#!/bin/sh\nexit 0\n"
    src_file = tmp_path / "src-bin"
    src_file.write_bytes(payload)
    missing_a = (tmp_path / "missing-a").as_uri()
    missing_b = (tmp_path / "missing-b").as_uri()
    dest = tmp_path / "out" / "tool"

    rc = verified_download.main(
        [
            "--urls",
            f"{missing_a},{missing_b}\n{src_file.as_uri()}\n",
            "--sha256",
            _sha256(payload),
            "--executable",
            "--output",
            str(dest),
        ]
    )
    assert rc == 0
    assert dest.read_bytes() == payload
    assert bool(dest.stat().st_mode & stat.S_IXUSR)
    out = capsys.readouterr().out
    assert f"::warning::Failed to fetch {missing_a}" in out
    assert f"::warning::Failed to fetch {missing_b}" in out


def test_falls_back_to_tgz_and_zip_archive_tuples_and_reuses_cached_file(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    payload = b"extracted-binary-data"
    member_file = tmp_path / "member"
    member_file.write_bytes(payload)
    tgz_path = tmp_path / "archive.tgz"
    with tarfile.open(tgz_path, "w:gz") as tar:
        tar.add(member_file, arcname="pkg/tool")

    missing_url = (tmp_path / "missing").as_uri()
    digest = _sha256(payload)
    dest = tmp_path / "cached" / "tool"
    sources = [
        (missing_url, digest, ""),
        (tgz_path.as_uri(), digest, "pkg/tool"),
    ]

    asyncio.run(download_verified_file(dest, sources, executable=True, initial_delay=0))
    assert dest.read_bytes() == payload
    assert f"::warning::Failed to fetch {missing_url}" in capsys.readouterr().out

    # Second call with only a broken URL succeeds via SHA-256 cache match.
    asyncio.run(
        download_verified_file(
            dest,
            [(missing_url, digest, "")],
            executable=True,
            initial_delay=0,
        )
    )
    assert capsys.readouterr().out == ""

    # Verify zip archive_member tuple extraction as well.
    zip_path = tmp_path / "archive.zip"
    with zipfile.ZipFile(zip_path, "w") as zf:
        zf.writestr("bin/tool.exe", payload)
    zip_dest = tmp_path / "zip-out" / "tool.exe"
    asyncio.run(
        download_verified_file(
            zip_dest,
            [(zip_path.as_uri(), digest, "bin/tool.exe")],
            executable=True,
            initial_delay=0,
        )
    )
    assert zip_dest.read_bytes() == payload


def test_concurrent_downloads(tmp_path: Path) -> None:
    payload_a = b"tool-alpha"
    payload_b = b"tool-beta"
    src_a = tmp_path / "src_a"
    src_b = tmp_path / "src_b"
    src_a.write_bytes(payload_a)
    src_b.write_bytes(payload_b)
    dest_a = tmp_path / "out" / "a"
    dest_b = tmp_path / "out" / "b"

    async def _run_both() -> None:
        await asyncio.gather(
            download_verified_file(
                dest_a,
                [(src_a.as_uri(), _sha256(payload_a), "")],
                executable=True,
            ),
            download_verified_file(
                dest_b,
                [(src_b.as_uri(), _sha256(payload_b), "")],
                executable=True,
            ),
        )

    asyncio.run(_run_both())
    assert dest_a.read_bytes() == payload_a
    assert dest_b.read_bytes() == payload_b


def test_rejects_bad_sha256_and_exhausts_retries(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    src_file = tmp_path / "corrupted"
    src_file.write_bytes(b"corrupted")
    dest = tmp_path / "out"

    with pytest.raises(DownloadError, match="Failed to download after 2 attempts"):
        asyncio.run(
            download_verified_file(
                dest,
                [(src_file.as_uri(), "0" * 64, "")],
                max_attempts=2,
                initial_delay=0,
            )
        )

    out = capsys.readouterr().out
    assert "::warning::SHA-256 mismatch:" in out
    assert "::warning::Download failed (attempt 1/2)" in out
    assert not dest.exists()
