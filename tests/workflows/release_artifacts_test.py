"""Tests for release artifact manifest generation and archive bundling."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tarfile
from pathlib import Path

from python.runfiles import runfiles


def test_generate_artifacts_manifest(tmp_path: Path):
    generate_script = (
        runfiles.CreateOrRaise().root()
        / "rules_python/dev/release_artifacts/generate_artifacts_manifest.py"
    )

    artifacts_dir = tmp_path / "release-artifacts"
    artifacts_dir.mkdir(parents=True)
    manifest_file = tmp_path / "artifacts_manifest.bzl"

    linux_bin = artifacts_dir / "exe_zip_maker-x86_64-unknown-linux-gnu"
    linux_bin.write_bytes(b"linux-binary-contents")
    linux_sha = hashlib.sha256(b"linux-binary-contents").hexdigest()

    win_bin = artifacts_dir / "exe_zip_maker-x86_64-pc-windows-msvc.exe"
    win_bin.write_bytes(b"windows-binary-contents")
    win_sha = hashlib.sha256(b"windows-binary-contents").hexdigest()

    mac_bin = artifacts_dir / "exe_zip_maker-aarch64-apple-darwin"
    mac_bin.write_bytes(b"mac-binary-contents")
    mac_sha = hashlib.sha256(b"mac-binary-contents").hexdigest()

    subprocess.run(
        [
            str(generate_script),
            "2.4.0",
            str(artifacts_dir),
            str(manifest_file),
            "bazel-contrib/rules_python",
        ],
        check=True,
    )

    manifest_bzl = manifest_file.read_text(encoding="utf-8")
    _, marker, manifest_json = manifest_bzl.partition('ARTIFACTS_MANIFEST_JSON = """')
    assert marker
    manifest = json.loads(manifest_json.removesuffix('"""\n'))
    base_url = "https://github.com/bazel-contrib/rules_python/releases/download/2.4.0"
    assert manifest == {
        "artifacts": {
            "exe_zip_maker": [
                {
                    "exec_compatible_with": [
                        "@platforms//cpu:aarch64",
                        "@platforms//os:macos",
                    ],
                    "name": "exe_zip_maker_aarch64_apple_darwin",
                    "sha256": mac_sha,
                    "urls": [f"{base_url}/exe_zip_maker-aarch64-apple-darwin"],
                },
                {
                    "exec_compatible_with": [
                        "@platforms//cpu:x86_64",
                        "@platforms//os:windows",
                    ],
                    "name": "exe_zip_maker_x86_64_pc_windows_msvc",
                    "sha256": win_sha,
                    "urls": [f"{base_url}/exe_zip_maker-x86_64-pc-windows-msvc.exe"],
                },
                {
                    "exec_compatible_with": [
                        "@platforms//cpu:x86_64",
                        "@platforms//os:linux",
                    ],
                    "name": "exe_zip_maker_x86_64_unknown_linux_gnu",
                    "sha256": linux_sha,
                    "urls": [f"{base_url}/exe_zip_maker-x86_64-unknown-linux-gnu"],
                },
            ]
        }
    }


def test_create_archive_and_notes_with_manifest(tmp_path: Path):
    rf_root = runfiles.CreateOrRaise().root()
    archive_script = (
        rf_root / "rules_python/.github/workflows/create_archive_and_notes.sh"
    )
    module_bazel = rf_root / "rules_python/MODULE.bazel"

    repo_dir = tmp_path / "repo"
    repo_dir.mkdir()
    shutil.copy2(module_bazel, repo_dir / "MODULE.bazel")
    (repo_dir / "python/private").mkdir(parents=True)
    (repo_dir / "python/private/artifacts_manifest.bzl").write_text(
        'ARTIFACTS_MANIFEST_JSON = ""\n', encoding="utf-8"
    )
    (repo_dir / "README.md").write_text("# rules_python\n", encoding="utf-8")

    subprocess.run(["git", "init"], cwd=repo_dir, check=True)
    subprocess.run(
        ["git", "config", "user.email", "test@example.com"],
        cwd=repo_dir,
        check=True,
    )
    subprocess.run(
        ["git", "config", "user.name", "Test User"],
        cwd=repo_dir,
        check=True,
    )
    subprocess.run(
        [
            "git",
            "add",
            "MODULE.bazel",
            "python/private/artifacts_manifest.bzl",
            "README.md",
        ],
        cwd=repo_dir,
        check=True,
    )
    subprocess.run(["git", "commit", "-m", "initial"], cwd=repo_dir, check=True)
    subprocess.run(["git", "tag", "2.4.0"], cwd=repo_dir, check=True)
    subprocess.run(
        ["git", "remote", "add", "origin", str(repo_dir)],
        cwd=repo_dir,
        check=True,
    )

    manifest_content = 'ARTIFACTS_MANIFEST_JSON = """{"artifacts": {}}"""\n'
    (repo_dir / "artifacts_manifest.bzl").write_text(manifest_content, encoding="utf-8")

    subprocess.run(
        [str(archive_script), "2.4.0"],
        cwd=repo_dir,
        check=True,
    )

    archive_path = repo_dir / "rules_python-2.4.0.tar.gz"
    assert archive_path.exists()

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        assert names.count("rules_python-2.4.0/MODULE.bazel") == 1
        assert (
            names.count("rules_python-2.4.0/python/private/artifacts_manifest.bzl") == 1
        )

        manifest_member = tar.extractfile(
            "rules_python-2.4.0/python/private/artifacts_manifest.bzl"
        )
        assert manifest_member is not None
        archived_manifest = manifest_member.read().decode("utf-8")
        assert archived_manifest == manifest_content

        module_member = tar.extractfile("rules_python-2.4.0/MODULE.bazel")
        assert module_member is not None
        archived_module = module_member.read().decode("utf-8")
        assert "\nTOOL_DEPS_DEV_ONLY = True\n" in archived_module
        assert "\nTOOL_DEPS_DEV_ONLY = False\n" not in archived_module
